# syntax=docker/dockerfile:1

# Stage 1: compile TypeScript and run the unit tests. The compiler and the
# test files never reach the runtime image.
FROM node:25-trixie-slim@sha256:aabbe39553d15ede8a97cc60c9e1a97034ff772afcf696ea42b94e7f5f2ec71b AS build
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json ./
COPY src ./src
COPY test ./test
RUN npm test \
    && mkdir -p /out \
    && cp -r dist/src /out/src \
    && cp package.json /out/

# Stage 2: distroless Node.js runtime. No shell, no package manager, runs as
# the nonroot user (65532). The app has no runtime dependencies, so there is
# no node_modules to copy.
FROM gcr.io/distroless/nodejs24-debian13:nonroot@sha256:bb6b03d81066993293a10feda7250e8e1cc034035fe9b61cfceededa7c8bf04d
ARG APP_VERSION=dev
ENV NODE_ENV=production \
    PORT=8080 \
    APP_VERSION=${APP_VERSION}
WORKDIR /srv
COPY --from=build --chown=root:root /out ./
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/nodejs/bin/node", "src/healthcheck.js"]
# The distroless entrypoint is already the node binary.
CMD ["src/main.js"]
