FROM golang:1.22-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/portfolio-sample ./cmd/portfolio-sample

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/portfolio-sample /portfolio-sample
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/portfolio-sample"]
