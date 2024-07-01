# base image
FROM ollama/ollama:latest

# build-time variable
ARG MODEL_NAME

RUN nohup bash -c "ollama serve &" && sleep 5 && ollama pull ${MODEL_NAME}

# Expose the port
EXPOSE 11434
