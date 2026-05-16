FROM node:20-alpine
WORKDIR /app
COPY backend/package.json ./
RUN npm install
COPY backend/ .
RUN mkdir -p data
EXPOSE 8787
CMD ["node", "server.js"]
