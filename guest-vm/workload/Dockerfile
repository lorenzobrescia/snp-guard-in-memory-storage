# Use a minimal base image
FROM alpine:latest

# Set the working directory
WORKDIR /app

# Command to write "Hello, World!" to a file when the container starts
CMD echo "Hello $(cat name.txt)" > /app/hello.txt