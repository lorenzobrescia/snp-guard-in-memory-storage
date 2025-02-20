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

# Define the workload
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

# Create the database directory
RUN mkdir -p /app/db

WORKDIR /app/YCSB

# run the DB workload
CMD ["sh", "-c", "./bin/ycsb run rocksdb -P workloads/romedium -p rocksdb.dir=/app/db > ../log.txt;"]