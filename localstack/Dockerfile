# base image
FROM ollama/ollama:latest

# build-time variable
ARG MODEL_NAME

# Allow requests from the frontend served from S3
ENV OLLAMA_ORIGINS="*"

# Start the server in the background, wait until it answers, then pull the model into the image
RUN ollama serve & \
    for i in $(seq 1 60); do ollama list > /dev/null 2>&1 && break; sleep 1; done && \
    ollama pull ${MODEL_NAME}

# Expose the port
EXPOSE 11434
