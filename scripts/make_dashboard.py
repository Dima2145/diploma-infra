#!/usr/bin/env python3
import json, sys, os, urllib.request

def load_env(path):
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())

load_env(os.path.join(os.path.dirname(__file__), "..", ".env"))

ZBX_URL = os.environ["ZBX_URL"]   # без дефолта: если нет в .env — скрипт честно упадёт
TOKEN   = os.environ["ZBX_TOKEN"]

# Все шесть хостов фермы. Встроенный дубликат "Zabbix server" удалён из UI —
# zabbix-01 мониторится как обычный хост (активный агент), бастион добавлен.
HOSTS = ["web-01", "web-02", "elastic-01", "kibana-01", "zabbix-01", "bastion"]
W, H  = 36, 5   # сетка дашборда 72 юнита: два виджета в ряд

def call(method, params):
    payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": 1}
    req = urllib.request.Request(ZBX_URL, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json-rpc",
                                          "Authorization": f"Bearer {TOKEN}"})
    resp = json.loads(urllib.request.urlopen(req).read())
    if "error" in resp:
        sys.exit(f"API error ({method}): {resp['error']}")
    return resp["result"]

# (имя виджета, x, [ [цвет, item-паттерн], ... ])
# Nginx-метрики есть только на web-01/web-02 — на остальных хостах график
# просто не покажет лишних линий, это норма.
WIDGETS = [
    ("CPU Utilization",    0,  [["FF465C", "CPU utilization"]]),
    ("CPU Saturation",    36,  [["1999C0", "Load average (1m avg)"],
                               ["04AC9D", "Load average (5m avg)"]]),
    ("CPU iowait",         0,  [["FFA97F", "CPU iowait time"]]),
    ("RAM Utilization",   36,  [["5E35B1", "Memory utilization"]]),
    ("RAM Saturation",     0,  [["E53935", "Free swap space in %"]]),
    ("Disk Utilization",  36,  [["4CAF50", "FS [/]: Space: Used, in %"]]),
    ("Disk Saturation",    0,  [["00BFFF", "vda: Disk utilization"],
                               ["9CCC65", "vda: Disk read request avg waiting time (r_await)"],
                               ["FF465C", "vda: Disk write request avg waiting time (w_await)"]]),
    ("Network Util",      36,  [["1999C0", "Interface eth0: Bits received"],
                               ["E57373", "Interface eth0: Bits sent"]]),
    ("Network Errors",     0,  [["E53935", "Interface eth0: Inbound packets with errors"],
                               ["E53935", "Interface eth0: Outbound packets with errors"],
                               ["FFA726", "Interface eth0: Inbound packets discarded"],
                               ["FB8C00", "Interface eth0: Outbound packets discarded"]]),
    ("HTTP Utilization",  36,  [["4DB6AC", "Connections active"]]),
    ("HTTP Saturation",    0,  [["9CCC65", "Connections reading"],
                               ["FFB300", "Connections writing"],
                               ["90CAF9", "Connections waiting"]]),
    ("HTTP Throughput",   36,  [["7E57C2", "Requests per second"]]),
]

def widget_fields(datasets):
    f = []
    for j, (color, pattern) in enumerate(datasets):
        f.append({"type": 1, "name": f"ds.{j}.color", "value": color})
        f.append({"type": 0, "name": f"ds.{j}.width", "value": 2})
        for k, host in enumerate(HOSTS):
            f.append({"type": 1, "name": f"ds.{j}.hosts.{k}", "value": host})
        f.append({"type": 1, "name": f"ds.{j}.items.0", "value": pattern})
    f.append({"type": 0, "name": "show_problems", "value": 1})
    f.append({"type": 1, "name": "time_period.from", "value": "now-3h"})
    f.append({"type": 1, "name": "time_period.to", "value": "now"})
    return f

refs = iter("BCDGHJKLMNPQVWXYZ")
widgets = []
for row, (name, x, datasets) in enumerate(WIDGETS):
    widgets.append({
        "type": "svggraph", "name": name,
        "x": x, "y": row * H, "width": W, "height": H, "view_mode": 0,
        "fields": widget_fields(datasets) + [
            {"type": 1, "name": "reference", "value": next(refs) * 5}
        ],
    })

found = call("dashboard.get", {"output": ["dashboardid", "name"],
                               "filter": {"name": "Web infra USE"}})
body = {"pages": [{"widgets": widgets}]}
if found:
    call("dashboard.update", {"dashboardid": found[0]["dashboardid"], **body})
    print(f"Dashboard 'Web infra USE' updated (id {found[0]['dashboardid']})")
else:
    res = call("dashboard.create", {"name": "Web infra USE", **body})
    print("Dashboard 'Web infra USE' created:", res["dashboardids"])

# ---------- Триггеры-пороги (thresholds по заданию) ----------
TRIGGERS = [
    ("High CPU utilization (>80% for 5m)", "system.cpu.util", "avg(/{h}/system.cpu.util,5m)>80", 4),
    ("Memory utilization high (>90%)",     "vm.memory.util",  "last(/{h}/vm.memory.util)>90",    3),
]

for h in HOSTS:
    found_h = call("host.get", {"filter": {"host": h}, "output": ["hostid"]})
    if not found_h:
        print(f"[skip] {h}: нет в Zabbix (не зарегистрирован?)")
        continue
    hostid = found_h[0]["hostid"]

    for desc, key, expr_tpl, prio in TRIGGERS:
        items = call("item.get", {"hostids": hostid, "search": {"key_": key},
                                  "output": ["key_"]})
        if not items:
            print(f"[skip] {h}: нет item'а {key}")
            continue
        full_desc = f"{h}: {desc}"
        if call("trigger.get", {"hostids": hostid,
                                "filter": {"description": full_desc}}):
            print(f"[exists] триггер '{full_desc}'")
            continue
        call("trigger.create", {
            "description": full_desc,
            "expression": expr_tpl.format(h=h),
            "priority": prio})
        print(f"[ok] триггер '{full_desc}'")

    # В шаблоне ключ vfs.fs.dependent.size[/,pused], ищем по подстроке —
    # сработает на любом варианте шаблона
    fs_items = call("item.get", {"hostids": hostid,
                                 "search": {"key_": "vfs.fs"},
                                 "output": ["key_"]})
    pused = sorted({i["key_"] for i in fs_items
                    if i["key_"].startswith("vfs.fs") and i["key_"].endswith("[/,pused]")})
    if not pused:
        print(f"[skip] {h}: нет item'а pused для /")
        continue
    full_desc = f"{h}: Root FS almost full (>90%)"
    expr = f"last(/{h}/{pused[0]})>90"
    if call("trigger.get", {"hostids": hostid,
                            "filter": {"description": full_desc}}):
        print(f"[exists] триггер '{full_desc}'")
    else:
        call("trigger.create", {
            "description": full_desc,
            "expression": expr,
            "priority": 3})
        print(f"[ok] триггер '{full_desc}' (ключ {pused[0]})")
