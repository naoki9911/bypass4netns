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
                latencies = line.split(" ")[5].split("/")
                data["min"] = int(latencies[0]) / 1000
                data["median"] = int(latencies[1]) / 1000
                data["75th"] = int(latencies[2]) / 1000
                data["95th"] = int(latencies[3]) / 1000
                data["99th"] = int(latencies[4]) / 1000
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
labels=['min', 'median', '75th', '95th', '99th']

data_num = len(data_files)
factor = (data_num+1) * BAR_WIDTH

plt.rcParams["figure.figsize"] = (8,5)
plt.rcParams["font.size"] = 18
plt.ylabel("Latency\n(millisecond)")

order = [0, 3, 1, 4, 2, 5]
for i in order:
    name = data_files[i]
    data = load_datas(name)
    value = []
    for l in labels:
        value.append(data[l])
    plt.bar([x*factor+(BAR_WIDTH*i) for x in range(0, len(labels))], value, align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label=name, color=colors[i], hatch=patterns[i]*3)

plt.legend(loc='upper center', bbox_to_anchor=(.5, -.10), ncol=len(data_files)/2, fontsize=12)
plt.xlim(0, (len(labels)-1)*factor+BAR_WIDTH*data_num)
plt.xticks([x*factor+BAR_WIDTH*data_num/2 for x in range(0, len(labels))], labels)
plt.tight_layout()

plt.savefig("rabbitmq_latency.png")
plt.savefig("rabbitmq_latency.pdf")
