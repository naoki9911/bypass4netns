import matplotlib.pyplot as plt
import numpy as np 
import csv
import sys
import re
import glob

BAR_WIDTH=0.25

def load_data(filename):
    data = {}
    with open(filename) as f:
        line = f.readline()
        while line:
            line = re.sub('\s+', ' ', line.strip()).split(" ")
            if "transactions:" in line:
                data["transactions"] = float(line[2].replace("(", ""))
            if "queries:" in line:
                data["queries"] = float(line[2].replace("(", ""))
            if "avg:" in line:
                data["latency(ms)"] = float(line[1])
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
data_files = ["rootful-pfd", "rootless-pfd", "b4ns-pfd", "rootful-vxlan", "rootless-vxlan", "b4ns-multinode"]
labels=['transactions', 'queries', 'latency(ms)']

plt.rcParams["font.size"] = 18
data_num = len(data_files) 
factor = (data_num+1) * BAR_WIDTH

datas = []
for i in range(0, data_num):
    data = load_datas(data_files[i])
    datas.append(data)

fig = plt.figure()
ax1 = fig.add_subplot()
ax1.set_ylabel("Operations / second")
ax2 = ax1.twinx()
ax2.set_ylabel("Average latency (ms)")

order = [0, 3, 1, 4, 2, 5]
for i in order:
    name = data_files[i]
    ax1.bar([BAR_WIDTH*i, factor+BAR_WIDTH*i], [datas[i][labels[0]], datas[i][labels[1]]], align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label=name, color=colors[i], hatch=patterns[i]*3)

for i in order:
    name = data_files[i]
    ax2.bar([factor*2+BAR_WIDTH*i], datas[i][labels[2]], align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label=name, color=colors[i], hatch=patterns[i]*3)

h1, l1 = ax1.get_legend_handles_labels()
ax1.legend(h1, l1, loc='upper center', bbox_to_anchor=(.5, -.10), ncol=len(data_files)/2, fontsize=12)
plt.xlim(0, (len(labels)-1)*factor+BAR_WIDTH*data_num)
plt.xticks([x*factor+BAR_WIDTH*data_num/2 for x in range(0, len(labels))], labels)
plt.tight_layout()

plt.savefig("mysql.png")
plt.savefig("mysql.pdf")
