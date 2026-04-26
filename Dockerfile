FROM node:20

# Create app dir
WORKDIR /app

# Copy package files first (layer caching)
COPY package.json package-lock.json* ./

# Install deps
RUN npm install

# Install solc locally (critical: avoids network fetch)
RUN npm install solc@0.8.23

# Copy rest of project
COPY . .

# Hardhat cache location fix (optional)
RUN mkdir -p /root/.cache/hardhat-nodejs

CMD ["npx", "hardhat", "compile"]













