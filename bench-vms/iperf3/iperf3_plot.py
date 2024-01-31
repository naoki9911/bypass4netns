import matplotlib.pyplot as plt
import numpy as np 
import json
import sys
import glob


BAR_WIDTH=0.2

def load_data(filename):
    with open(filename) as f:
        try:
            return json.load(f)
        except Exception:
            f.seek(0)
            l = f.readlines()
            if l[0] == "FAIL":
                return None


def load_datas(prefix):
    files = glob.glob("*{}*".format(prefix))
    data = {}
    cnt = 0
    rcv_bps = 0
    for file in files:
        d = load_data(file)
        if d == None:
            return None
        if "error"  in d:
            return None
        rcv_bps += d["end"]["sum_received"]["bits_per_second"]
        cnt += 1
    data["rcv_bps"] = rcv_bps / cnt
    return data


patterns = [ "/" , "\\" , "|" , "-" , "+" , "x", "o", "O", ".", "*" ]
colors = ["slategray", "royalblue", "orange", "slategray", "royalblue", "orange"]
datas = ["rootful-pfd", "rootless-pfd", "b4ns-pfd", "rootful-vxlan", "rootless-vxlan", "b4ns-multinode"]
labels=['1', '2', '4', '8']

#plt.rcParams["figure.figsize"] = (6.6,8)
plt.rcParams["font.size"] = 18
plt.ylabel("Throughput (Gbps)")
plt.xlabel("Number of parallel streams")

data_num = len(datas)
factor = (data_num+1) * BAR_WIDTH
order = [0, 3, 1, 4, 2, 5]
for i in order:
    value = []
    label_idx = 0
    for l in labels:
        data_json = load_datas('{}-p{}'.format(datas[i], l))

        # error tests are treated as 0
        if data_json == None:
            value.append(0)
            plt.text(label_idx*factor+(BAR_WIDTH*i)+0.025, 0, "X", fontsize=14)
        else:
            value.append(data_json["rcv_bps"] / 1024 / 1024 / 1024)
        label_idx += 1
    print("{}:{}".format(datas[i], value[0]))

    plt.bar([x*factor+(BAR_WIDTH*i) for x in range(0, len(labels))], value, color=colors[i], align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label=datas[i], hatch=patterns[i]*3)


plt.legend(loc='upper center', bbox_to_anchor=(.5, -.25), ncol=len(datas)/2, fontsize=12)
plt.xlim(0, (len(labels)-1)*factor+BAR_WIDTH*data_num)
plt.xticks([x*factor+BAR_WIDTH*data_num/2 for x in range(0, len(labels))], labels)
plt.tight_layout()

plt.savefig("iperf3.png")
plt.savefig("iperf3.pdf")
