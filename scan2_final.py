import threading
import socket
import time
import os
from datetime import datetime
import json

CONST_MAX_PORTS = 65534
CONST_START_THREAD_TIMEOUT = 0.7
CONST_TCP_WAIT_TIMEOUT = 1
CONST_NETWORKS_FILE = "networks.txt"
CONST_LOG_FILE = "port_scan_log.txt"
CONST_RESULT_FILE = "result.json"
#TG_STR_1 = "wget -O /dev/null \"https://api.telegram.org/bot0000000000:KEY/sendMessage?chat_id=-11111111111111&disable_notification=true&text="
TG_STR_1 = "wget -O /dev/null \"https://api.telegram.org/bot000000000:KEY/sendMessage?chat_id=-111111111111&disable_notification=true&text="
TG_STR_2 = "\""


def log(log_string):
    file_name = CONST_LOG_FILE
    if log_string == "_INIT_":
        newfile = open(file_name, 'w')
        newfile.truncate()
        newfile.close()
    else:
        file_log = open(file_name, 'a')
        month_names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        dt = datetime.now()
        if dt.hour < 10:
            f_hour = f"0{dt.hour}"
        else:
            f_hour = f"{dt.hour}"
        if dt.minute < 10:
            f_minute = f"0{dt.minute}"
        else:
            f_minute = f"{dt.minute}"
        if dt.second < 10:
            f_second = f"0{dt.second}"
        else:
            f_second = f"{dt.second}"
        file_str = f"{f_hour}:{f_minute}:{f_second} {dt.day}-{month_names[dt.month - 1]}-{dt.year} ... {log_string} \n"
        file_log.write(file_str)
        file_log.close()


def cidr_to_addrlist(act_network):
    addresses = list()
    act_network.strip()
    slash_position = act_network.find("/")
    network_name = act_network[:slash_position]
    network_mask = int(act_network[slash_position + 1:])
    if network_mask == 32:
        addresses.append(network_name)
    else:
        host_num = 2 ** (32 - network_mask) - 2
        net_ip_arr_str = network_name.split(".")
        net_ip_arr_int = [int(net_ip_arr_str[0]), int(net_ip_arr_str[1]), int(net_ip_arr_str[2]), int(net_ip_arr_str[3])]
        net_binary = (net_ip_arr_int[0] << 24) + (net_ip_arr_int[1] << 16) + (net_ip_arr_int[2] << 8) + net_ip_arr_int[3]
        for i in range(0, host_num, 1):
            net_binary += 1
            oct1 = net_binary >> 24
            oct2 = (net_binary % 16777216) >> 16
            oct3 = (net_binary % 65536) >> 8
            oct4 = net_binary % 256
            addresses.append(f"{oct1}.{oct2}.{oct3}.{oct4}")
    return addresses


#def worker_pinger(ip_address):
#    r = os.popen(f"ping -c2 -W1 {ip_address}").read()
#    if (" 0% packet loss," in r) or (" 50% packet loss," in r) or (" 25% packet loss," in r) or (" 75% packet loss," in r):
#        log(f"{ip_address} is alive")
#        alive_hosts.add(ip_address)
#    pinged_hosts.add(ip_address)


def worker_scan(host_address, start_port, end_port):
    opened_ports = list()
    for port in range(start_port, end_port+1, 1):
        connection = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        connection.settimeout(CONST_TCP_WAIT_TIMEOUT)
        is_opened = 0
        #print(f"{host_address}:{port}")
        try:
            connection.connect((host_address.strip(), port))
            is_opened = 1
            connection.close()
        except socket.error:
            pass
        if is_opened == 1:
            log(f"{host_address}:{port} is opened")
            opened_ports.append(port)
    if len(opened_ports) > 0:
        results[host_address] = opened_ports
    scanned_hosts.add(host_address)


# loading startup data
log("_INIT_")
log("START")
file = open(CONST_NETWORKS_FILE, "r")
networks_CIDR = file.read().strip().split()
file.close()
del file

# converting CIDR to set of IP addresses
ip_addresses = set()
for network_CIDR in networks_CIDR:
    ip_list = cidr_to_addrlist(network_CIDR)
    for ip in ip_list:
        ip_addresses.add(ip)
del ip
del ip_list

# pinging IP addresses
#ping_threads = set()
#pinged_hosts = set()
#alive_hosts = set()
#for ip in ip_addresses:
#    ping_threads.add(threading.Thread(target=worker_pinger, args=(ip, )))
#for pinger_thread in ping_threads:
#    pinger_thread.start()
#    time.sleep(CONST_START_THREAD_TIMEOUT)

#while len(pinged_hosts) != len(ip_addresses):
#    time.sleep(1)

#for pinger_thread in ping_threads:
#    pinger_thread.join()

#del ip_addresses
#del pinger_thread
#del pinged_hosts
#del ping_threads
#del ip

# scanning living hosts
scan_threads = set()
scanned_hosts = set()
results = dict()
for host in ip_addresses:
    scan_threads.add(threading.Thread(target=worker_scan, args=(host, 1, CONST_MAX_PORTS)))

for scan_thread in scan_threads:
    time.sleep(CONST_START_THREAD_TIMEOUT)
    scan_thread.start()

last_scanned_hosts = 0
while len(scanned_hosts) != len(ip_addresses):
    currently_scanned_hosts = len(scanned_hosts)
    if currently_scanned_hosts > last_scanned_hosts:
        log(f"scanned {currently_scanned_hosts} hosts")
        last_scanned_hosts = currently_scanned_hosts
    time.sleep(1)
del last_scanned_hosts
del currently_scanned_hosts

for scan_thread in scan_threads:
    scan_thread.join()

del scan_thread
del scan_threads
del scanned_hosts

# saving results
log("saving results")
first_time_scan = 0
if os.path.exists(CONST_RESULT_FILE):
    load = open(CONST_RESULT_FILE, "r")
    inner_dict = json.load(load)
    load.close()
else:
    inner_dict = dict()
    first_time_scan = 1

save = open(CONST_RESULT_FILE, "w")
json.dump(results, save, indent=4)
save.close()
#-------------------- Analyzing --------------------------------------
log("analysing the result")
old_dict = dict() # contains ips and ports closed since last scan
new_dict = dict() # contains ips and ports opened since last scan
for old_key in inner_dict.keys():
    if old_key not in results.keys():
        old_dict[old_key] = inner_dict[old_key]
for new_key in results.keys():
    if new_key not in inner_dict.keys():
        new_dict[new_key] = results[new_key]
    if (new_key in inner_dict.keys()) and (new_key in results.keys()):
        removed_ports = list()
        added_ports = list()
        for r_port in inner_dict[new_key]:
            if r_port not in results[new_key]:
                removed_ports.append(r_port)
        for a_port in results[new_key]:
            if a_port not in inner_dict[new_key]:
                added_ports.append(a_port)
        if len(removed_ports) > 0:
            old_dict[new_key] = list(removed_ports)
        if len(added_ports) > 0:
            new_dict[new_key] = list(added_ports)
        del removed_ports
        del added_ports

old_outstr = str()
for t_ip in old_dict:
    old_outstr += str(t_ip)
    old_outstr += ": "
    d_len = len(old_dict[t_ip])
    for t_port in old_dict[t_ip]:
        old_outstr += str(t_port)
        if t_port != old_dict[t_ip][d_len - 1]:
            old_outstr += ", "
    old_outstr += "\n"

new_outstr = str()
for t_ip in new_dict:
    new_outstr += str(t_ip)
    new_outstr += ": "
    d_len = len(new_dict[t_ip])
    for t_port in new_dict[t_ip]:
        new_outstr += str(t_port)
        if t_port != new_dict[t_ip][d_len - 1]:
            new_outstr += ", "
    new_outstr += "\n"

output_str = str()

if first_time_scan == 1:
    output_str = f"PORT SCANNER:\nFirst scan !!!\n{new_outstr}"
else:
    output_str = f"PORT SCANNER:\n"
    if len(old_outstr) > 0:
        output_str += f"closed since last scan:\n{old_outstr}\n"
    if len(new_outstr) > 0:
        output_str += f"opened since last scan:\n{new_outstr}\n"

wget_str = TG_STR_1 + output_str + TG_STR_2

if (len(old_outstr) > 0) or (len(new_outstr) > 0):
    r0 = os.popen(wget_str).read()
    time.sleep(1)
    del r0
#-------------------- End Analyzing ------------------------------------

log("END")
