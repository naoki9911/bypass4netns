import matplotlib.pyplot as plt
import numpy as np 
import csv
import sys
import glob

def load_data(filename):
    data = {}
    finished = False
    with open(filename) as f:
        line = f.readline()
        while line:
            line = line.strip()
            if "sending rate avg" in line:
                data["Sending"] = int(line.split(" ")[5])
                finished = True
            if "receiving rate avg" in line:
                data["Receiving"] = int(line.split(" ")[5])
                finished = True
            if finished and "consumer latency" in line:
                None
                #print(line.split(" ")[5])
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

BAR_WIDTH=0.25

patterns = [ "/" , "\\" , "|" , "-" , "+" , "x", "o", "O", ".", "*" ]
colors = ["slategray", "royalblue", "orange", "slategray", "royalblue", "orange"]
data_files = ["rootful-pfd", "rootless-pfd", "b4ns-pfd", "rootful-vxlan", "rootless-vxlan", "b4ns-multinode"]
labels=['Sending', 'Receiving']

data_num = len(data_files)
factor = (data_num+1) * BAR_WIDTH

datas = []
for i in range(0, data_num):
    data = load_datas(data_files[i])
    datas.append(data)

plt.rcParams["font.size"] = 18
fig = plt.figure()
ax1 = fig.add_subplot()
ax1.set_ylabel("messages / second")

order = [0, 3, 1, 4, 2, 5]
for i in order:
    name = data_files[i]
    ax1.bar([BAR_WIDTH*i, factor + BAR_WIDTH*i], [datas[i][labels[0]], datas[i][labels[0]]], align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label=name, color=colors[i], hatch=patterns[i]*3)

h1, l1 = ax1.get_legend_handles_labels()
ax1.legend(h1, l1, loc='upper center', bbox_to_anchor=(.5, -.10), ncol=len(data_files)/2, fontsize=12)
plt.xlim(0, (len(labels)-1)*factor+BAR_WIDTH*data_num)
plt.xticks([x*factor+BAR_WIDTH*data_num/2 for x in range(0, len(labels))], labels)
plt.tight_layout()

plt.savefig("rabbitmq.png")
plt.savefig("rabbitmq.pdf")
