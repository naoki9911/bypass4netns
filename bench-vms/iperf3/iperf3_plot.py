import matplotlib.pyplot as plt
import numpy as np 
import json
import sys
import glob


BAR_WIDTH=0.2

def load_data(filename):
    with open(filename) as f:
        return json.load(f)

def load_datas(prefix):
    files = glob.glob("*{}*".format(prefix))
    data = {}
    cnt = 0
    rcv_bps = 0
    for file in files:
        d = load_data(file)
        rcv_bps += d["end"]["sum_received"]["bits_per_second"]
        cnt += 1
    data["rcv_bps"] = rcv_bps / cnt
    return data


patterns = [ "/" , "\\" , "|" , "-" , "+" , "x", "o", "O", ".", "*" ]
colors = ["slategray", "royalblue", "orange", "slategray", "royalblue", "orange"]
datas = ["rootful-pfd", "rootless-pfd", "b4ns-pfd", "rootful-vxlan", "rootless-vxlan", "b4ns-multinode"]
labels=['']

#plt.rcParams["figure.figsize"] = (6.6,8)
plt.rcParams["font.size"] = 18
plt.ylabel("Throughput (Gbps)")

data_num = len(datas)
factor = (data_num+1) * BAR_WIDTH
order = [0, 3, 1, 4, 2, 5]
for i in order:
    data_json = load_datas(datas[i])
    value = [data_json["rcv_bps"] / 1024 / 1024 / 1024]
    print("{}:{}".format(datas[i], value[0]))

    plt.bar([x*factor+(BAR_WIDTH*i) for x in range(0, len(labels))], value, color=colors[i], align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label=datas[i], hatch=patterns[i]*3)


plt.legend(loc='upper center', bbox_to_anchor=(.5, -.10), ncol=len(datas)/2, fontsize=12)
plt.xlim(0, (len(labels)-1)*factor+BAR_WIDTH*data_num)
plt.xticks([x*factor+BAR_WIDTH*data_num/2 for x in range(0, len(labels))], labels)
plt.tight_layout()

plt.savefig("iperf3.png")
plt.savefig("iperf3.pdf")
