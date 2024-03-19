import matplotlib.pyplot as plt
import numpy as np
import json
import sys
import glob

BAR_WIDTH=0.25

def load_data(filename):
    data = {}
    with open(filename) as f:
        line = f.readline()
        while line:
            for l in json.loads(line):
                gbps = l["totalSize"] * 8 / l["totalElapsedSecond"] / 1024 / 1024 / 1024
                file = l["url"].split("/")[3]
                if file not in data:
                    data[file] = 0.0
                data[file] += gbps
            line = f.readline()
    return data

def load_datas(prefix):
    files = glob.glob("*{}*".format(prefix))
    data = {}
    cnt = 0
    for file in files:
        d = load_data(file)
        for l in d:
            if l not in data:
                data[l] = 0
            data[l] += d[l]
        cnt += 1
    
    for l in data:
        data[l] /= cnt
    return data


patterns = [ "/" , "\\" , "|" , "-" , "+" , "x", "o", "O", ".", "*" ]
colors = ["slategray", "royalblue", "orange", "slategray", "royalblue", "orange"]
datas = ["rootful-pfd", "rootless-pfd", "b4ns-pfd", "rootful-vxlan", "rootless-vxlan", "b4ns-multinode"]
#labels=['blk-1k', 'blk-32k', 'blk-512k', 'blk-1m', 'blk-32m', 'blk-128m', 'blk-512m', 'blk-1g']
#labels_plot=['1KiB', '32KiB', '512KiB', '1MiB', '32MiB', '128MiB', '512MiB', '1GiB']
labels=['blk-32k', 'blk-512k', 'blk-1m','blk-128m', 'blk-512m', 'blk-1g']
labels_plot=['32KiB', '512KiB', '1MiB', '128MiB', '512MiB', '1GiB']

plt.rcParams["figure.figsize"] = (6.5,5)
plt.rcParams["font.size"] = 18
plt.ylabel("Throughput (Gbps)")
plt.xlabel("File size", fontsize=16)

data_num = len(datas)
factor = (data_num+1) * BAR_WIDTH
order = [0, 3, 1, 4, 2, 5]
for i in order:
    name = datas[i]
    data = load_datas(name)
    value = []
    for l in labels:
        if l == "blk-1g":
            print("name={} data={} value={}".format(name, l, data[l]))
        value.append(data[l])
    plt.bar([x*factor+(BAR_WIDTH*i) for x in range(0, len(labels))], value, align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label=name, color=colors[i], hatch=patterns[i]*3)

plt.legend(loc='upper center', bbox_to_anchor=(.45, -.15), ncol=len(datas)/2, fontsize=12)
plt.xlim(0, (len(labels)-1)*factor+BAR_WIDTH*data_num)
plt.xticks([x*factor+BAR_WIDTH*data_num/2 for x in range(0, len(labels))], labels_plot, fontsize=14)
plt.tight_layout()

plt.savefig("block.png", dpi=400)
plt.savefig("block.pdf")
