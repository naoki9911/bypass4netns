import matplotlib.pyplot as plt
import numpy as np 
import csv
import sys
import glob

def load_data(filename):
    data = {}
    with open(filename) as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            data[row[0]] = float(row[2])
    return data

BAR_WIDTH=0.25

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
labels_for_data=['PING_INLINE', 'PING_MBULK', 'SET', 'GET', 'INCR', 'LPUSH', 'RPUSH', 'LPOP', 'RPOP', 'SADD', 'HSET', 'SPOP', 'ZADD', 'ZPOPMIN', 'LPUSH (needed to benchmark LRANGE)', 'LRANGE_100 (first 100 elements)', 'LRANGE_300 (first 300 elements)', 'LRANGE_500 (first 500 elements)', 'LRANGE_600 (first 600 elements)', 'MSET (10 keys)', 'XADD']
labels=['PING\n_INLINE', 'PING\n_MBULK', 'SET', 'GET', 'INCR', 'LPUSH', 'RPUSH', 'LPOP', 'RPOP', 'SADD', 'HSET', 'SPOP', 'ZADD', 'ZPOPMIN', 'LPUSH', 'LRANGE\n_100', 'LRANGE\n_300', 'LRANGE\n_500', 'LRANGE\n_600', 'MSET\n(10 keys)', 'XADD']

plt.rcParams["figure.figsize"] = (20,4)
plt.rcParams["font.size"] = 18
plt.ylabel("Average latency\n(milliseconds)")

data_num = len(datas)
factor = (data_num+1) * BAR_WIDTH
order = [0, 1, 2, 3, 4, 5]
for i in order:
    name = datas[i]
    data_csv = load_datas(name)
    value = []
    for l in labels_for_data:
        value.append(data_csv[l])
    plt.bar([x*factor+(BAR_WIDTH*i) for x in range(0, len(labels))], value, align="edge",  edgecolor="black", linewidth=1, width=BAR_WIDTH, label=name, color=colors[i], hatch=patterns[i]*3)

plt.legend(loc='upper center', bbox_to_anchor=(.5, -.16), ncol=len(datas), fontsize=14)
plt.xlim(0, (len(labels)-1)*factor+BAR_WIDTH*data_num)
plt.xticks([x*factor+BAR_WIDTH*data_num/2 for x in range(0, len(labels))], labels, fontsize=14)
plt.tight_layout()

plt.savefig("redis_latency.png")
plt.savefig("redis_latency.pdf")
