FROM docker.n8n.io/n8nio/n8n:stable

USER root
RUN apk add --no-cache python3 && \
    npm install -g cheerio
USER node
