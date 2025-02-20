FROM ubuntu:jammy

# Install dependencies
RUN apt-get update && \
    apt-get install -y maven git librocksdb-dev python3 && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Clone YCSB repository and build the RocksDB binding
RUN git clone https://github.com/brianfrankcooper/YCSB.git && \
    cd YCSB && \
    mvn -pl site.ycsb:rocksdb-binding -am clean package

RUN echo "\
recordcount=100000\n\
operationcount=100000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
readproportion=1\n\
updateproportion=0\n\
scanproportion=0\n\
insertproportion=0\n\
requestdistribution=zipfian" > /app/YCSB/workloads/rosmall

RUN echo "\
recordcount=5000000\n\
operationcount=5000000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
readproportion=1\n\
updateproportion=0\n\
scanproportion=0\n\
insertproportion=0\n\
requestdistribution=zipfian" > /app/YCSB/workloads/romedium

RUN echo "\
recordcount=10000000\n\
operationcount=10000000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
readproportion=1\n\
updateproportion=0\n\
scanproportion=0\n\
insertproportion=0\n\
requestdistribution=zipfian" > /app/YCSB/workloads/robig

RUN echo "\
recordcount=100000\n\
operationcount=100000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
writeallfields=true\n\
readproportion=0\n\
scanproportion=0\n\
updateproportion=0.8\n\
insertproportion=0.2\n\
requestdistribution=zipfian" > /app/YCSB/workloads/wosmall

RUN echo "\
recordcount=5000000\n\
operationcount=5000000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
writeallfields=true\n\
readproportion=0\n\
scanproportion=0\n\
updateproportion=0.8\n\
insertproportion=0.2\n\
requestdistribution=zipfian" > /app/YCSB/workloads/womedium

RUN echo "\
recordcount=10000000\n\
operationcount=10000000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
writeallfields=true\n\
readproportion=0\n\
scanproportion=0\n\
updateproportion=0.8\n\
insertproportion=0.2\n\
requestdistribution=zipfian" > /app/YCSB/workloads/wobig

RUN echo "\
recordcount=5000000\n\
operationcount=5000000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
writeallfields=true\n\
readproportion=0.5\n\
scanproportion=0\n\
updateproportion=0.5\n\
insertproportion=0\n\
requestdistribution=zipfian" > /app/YCSB/workloads/mediumA

RUN echo "\
recordcount=5000000\n\
operationcount=5000000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
writeallfields=true\n\
readproportion=0.95\n\
scanproportion=0\n\
updateproportion=0.05\n\
insertproportion=0\n\
requestdistribution=zipfian" > /app/YCSB/workloads/mediumB

RUN echo "\
recordcount=5000000\n\
operationcount=5000000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
writeallfields=true\n\
readproportion=0.95\n\
scanproportion=0\n\
updateproportion=0\n\
insertproportion=0.05\n\
requestdistribution=zipfian" > /app/YCSB/workloads/mediumD

RUN echo "\
recordcount=5000000\n\
operationcount=5000000\n\
fieldcount=10\n\
fieldlength=100\n\
workload=site.ycsb.workloads.CoreWorkload\n\
readallfields=true\n\
writeallfields=true\n\
readproportion=0.5\n\
scanproportion=0\n\
updateproportion=0\n\
insertproportion=0\n\
readmodifywriteproportion=0.5\n\
requestdistribution=zipfian" > /app/YCSB/workloads/mediumF

# Create the database directory
RUN mkdir -p /app/db

WORKDIR /app/YCSB

# run the DB workload
CMD ["sh", "-c", "start=$(date +%s%N); ./bin/ycsb run rocksdb -P workloads/rosmall -p rocksdb.dir=/app/db > ../log.txt; end=$(date +%s%N); echo $(( (end - start) / 1000000 )) ms > ../time.txt"]