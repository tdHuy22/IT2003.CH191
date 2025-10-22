FROM node:20-alpine

WORKDIR /app

COPY package*.json ./

COPY logs /app/logs

RUN npm install --production

COPY . .

RUN mkdir -p /app/logs /app/certs/express


EXPOSE 3001

CMD ["node", "server.js"]