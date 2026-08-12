# The frontend runs the Vite dev server rather than a production build.
#
# That is deliberate: during the demo Copilot edits React source, and the dev
# server hot-reloads so the change is visible immediately. A production build
# would need a rebuild after every edit.

FROM node:22-alpine
WORKDIR /app

# npm ci against a committed lockfile, so every customer gets byte-identical
# dependencies and the demo cannot drift under them mid-presentation.
COPY package.json package-lock.json ./
RUN npm config set fetch-retries 5 \
    && npm config set fetch-retry-maxtimeout 120000 \
    && npm ci --no-audit --no-fund

COPY . .

EXPOSE 5173
CMD ["npm", "run", "dev"]
