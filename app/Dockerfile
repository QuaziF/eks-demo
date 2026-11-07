# syntax=docker/dockerfile:1

# ---- build stage: has the toolchain, never shipped ----
ARG GO_VERSION=1.26
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src

# Dependency manifest first, so this layer is cached until go.mod changes.
COPY go.mod ./
RUN go mod download

# Source last: the only layer that changes on a normal code edit.
COPY *.go ./
ARG VERSION=dev
ARG COMMIT=none
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux \
    go build -trimpath \
      -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
      -o /out/app .

# ---- runtime stage: static binary on a distroless, non-root base ----
FROM gcr.io/distroless/static-debian12:nonroot
ARG VERSION=dev
ARG COMMIT=none
LABEL org.opencontainers.image.title="demo-app" \
      org.opencontainers.image.description="Demo service for the containerization and orchestration demo" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${COMMIT}"

COPY --from=build /out/app /app
USER 65532:65532
EXPOSE 8080

# Distroless has no shell or curl, so the binary probes itself. Kubernetes ignores
# HEALTHCHECK and uses its own probes; this is for plain `docker run`.
HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --retries=3 \
  CMD ["/app", "-healthcheck"]

ENTRYPOINT ["/app"]
