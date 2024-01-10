import matplotlib.pyplot as plt
import numpy as np 
import csv
import sys
import glob
import re

def load_data(filename):
    data = {}
    cnt = 0
    with open(filename) as f:
        line = f.readline()
        while line:
            line = re.sub('\s+', ' ', line.strip()).split(" ")
            if "usr" not in data:
                data["usr"] = 0
            if "sys" not in data:
                data["sys"] = 0
            if "soft" not in data:
                data["soft"] = 0
            data["usr"] += float(line[2])
            data["sys"] += float(line[4])
            data["soft"] += float(line[7])
            cnt += 1
            line = f.readline()
    data["usr"] /= cnt
    data["sys"] /= cnt
    data["soft"] /= cnt
    return data

def load_datas(datas):
    res = {}
    for d in datas:
        files = glob.glob("*{}*".format(d))
        for file in files:
            res[d] = load_data(file)
    return res

BAR_WIDTH=0.2

patterns = [ "/" , "\\" , "|" , "-" , "+" , "x", "o", "O", ".", "*" ]
colors = ["slategray", "royalblue", "orange", "slategray", "royalblue", "orange"]
datas = ["rootful-pfd-client", "rootful-pfd-server", "rootless-pfd-client", "rootless-pfd-server", "b4ns-pfd-client", "b4ns-pfd-server"]

data = load_datas(datas)
usr_values = []
sys_values = []
soft_values = []
soft_bottom = []
for d in datas:
    usr_values.append(data[d]["usr"])
    sys_values.append(data[d]["sys"])
    soft_values.append(data[d]["soft"])
    soft_bottom.append(data[d]["usr"] + data[d]["sys"])

print(usr_values)
#plt.rcParams["figure.figsize"] = (6.6,8)
plt.rcParams["font.size"] = 18
plt.ylabel("CPU Usage (%)")

data_num = len(datas)
SPACE_WIDTH=0.1
plt.bar([(BAR_WIDTH + SPACE_WIDTH)*x for x in range(0, data_num)], usr_values, color="slategray", align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label="usr")
plt.bar([(BAR_WIDTH + SPACE_WIDTH)*x for x in range(0, data_num)], sys_values, bottom=usr_values, color="orange", align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label="sys")
plt.bar([(BAR_WIDTH + SPACE_WIDTH)*x for x in range(0, data_num)], soft_values, bottom=soft_bottom, color="royalblue", align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label="soft")


plt.legend(loc='upper center', bbox_to_anchor=(.5, -.15), ncol=len(datas)/2, fontsize=12)
plt.xlim(0, (BAR_WIDTH + SPACE_WIDTH)*data_num - SPACE_WIDTH)
labels = ["client      server\nrootful-pfd", "client      server\nrootless-pfd", "client      server\nb4ns-pfd"]

plt.xticks([(BAR_WIDTH + SPACE_WIDTH)*x*2+BAR_WIDTH+(SPACE_WIDTH/2) for x in range(0, len(labels))], labels, fontsize=12)
plt.tight_layout()

plt.savefig("iperf3_mpstat.png")
plt.savefig("iperf3_mpstat.pdf")
