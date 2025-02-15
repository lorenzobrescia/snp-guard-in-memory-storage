# Use the official Ubuntu Jammy base image
FROM ubuntu:jammy

# Set the working directory
WORKDIR /app

# Install tar (in case it's not already installed)
RUN apt-get update && apt-get install -y tar

# Extract the holly.tar.gz archive
CMD ["sh", "-c", "start=$(date +%s%N); tar -xzf to_decompress -C res/; end=$(date +%s%N); echo $(( (end - start) / 1000000 )) ms > time.txt"]