ifdef VERSION
else
	VERSION := $(shell sh -c 'git describe --always --tags')
endif

OUTPUT ?= dist/anycable-go

ifdef GOBIN
PATH := $(GOBIN):$(PATH)
else
PATH := $(subst :,/bin:,$(GOPATH))/bin:$(PATH)
endif

# Standard build
default: prepare build

# Install current version
install:
	go install ./...

build:
	env CGO_ENABLED=1 go build -ldflags "-s -w -X main.version=$(VERSION)" -o $(OUTPUT) cmd/anycable-go/main.go

prepare-mruby:
	(cd vendor/github.com/mitchellh/go-mruby && make)

build-linux:
	env CGO_ENABLED=0 GOOS=linux GOARCH=386 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-linux-386" cmd/anycable-go/main.go

build-all-mruby:
	env CGO_ENABLED=1 go build -ldflags "-s -w -X main.version=$(VERSION)" -o "dist/anycable-go-$(VERSION)-mrb-macos-amd64" cmd/anycable-go/main.go
	docker run --rm -v $(PWD):/go/src/github.com/anycable/anycable-go -w /go/src/github.com/anycable/anycable-go -e OUTPUT="dist/anycable-go-$(VERSION)-mrb-linux-amd64" amd64/golang:1.10 make build

build-all:
	rm -rf ./dist
	env CGO_ENABLED=0 GOOS=linux GOARCH=arm go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-linux-arm" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-linux-arm64" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=linux GOARCH=386 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-linux-386" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-linux-amd64" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=windows GOARCH=386 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-win-386" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-win-amd64" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=darwin GOARCH=386 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-macos-386" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-macos-amd64" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=freebsd GOARCH=arm go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-freebsd-arm" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=freebsd GOARCH=386 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-freebsd-386" cmd/anycable-go/main.go
	env CGO_ENABLED=0 GOOS=freebsd GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o "dist/anycable-go-$(VERSION)-freebsd-amd64" cmd/anycable-go/main.go

s3-deploy:
	aws s3 cp --acl=public-read ./dist/anycable-go-$(VERSION)-linux-amd64 "s3://anycable/builds/$(VERSION)/anycable-go-$(VERSION)-heroku"
	aws s3 cp --acl=public-read ./dist/anycable-go-$(VERSION)-mrb-linux-amd64 "s3://anycable/builds/$(VERSION)-mrb/anycable-go-$(VERSION)-mrb-heroku"

downloads-md:
	ruby etc/generate_downloads.rb

release: build-all s3-deploy dockerize

docker-release: dockerize
	docker push "anycable/anycable-go:$(VERSION)"

dockerize:
	CGO_ENABLED=0 GOOS=linux go build -ldflags "-X main.version=$(VERSION)" -a -installsuffix cgo -o .docker/anycable-go cmd/anycable-go/main.go
	docker build -t "anycable/anycable-go:$(VERSION)" .

# Run server
run:
	go run ./cmd/anycable-go/main.go

build-protos:
	protoc --proto_path=./etc --go_out=plugins=grpc:./protos ./etc/rpc.proto

test:
	go test github.com/anycable/anycable-go/cli \
		github.com/anycable/anycable-go/config \
		github.com/anycable/anycable-go/node \
		github.com/anycable/anycable-go/pool \
		github.com/anycable/anycable-go/pubsub \
		github.com/anycable/anycable-go/rpc \
		github.com/anycable/anycable-go/server \
		github.com/anycable/anycable-go/metrics \
		github.com/anycable/anycable-go/mrb \
		github.com/anycable/anycable-go/utils

test-cable:
	go build -o tmp/anycable-go-test cmd/anycable-go/main.go
	anyt -c "tmp/anycable-go-test --headers=cookie,x-api-token" --target-url="ws://localhost:8080/cable"
	anyt -c "tmp/anycable-go-test --headers=cookie,x-api-token --ssl_key=etc/ssl/server.key --ssl_cert=etc/ssl/server.crt --port=8443" --target-url="wss://localhost:8443/cable"

test-ci: prepare prepare-mruby test test-cable

# Get dependencies and use gdm to checkout changesets
prepare:
	go get -u github.com/golang/dep/cmd/dep
	dep ensure

gen-ssl:
	mkdir -p tmp/ssl
	openssl genrsa -out tmp/ssl/server.key 2048
	openssl req -new -x509 -sha256 -key tmp/ssl/server.key -out tmp/ssl/server.crt -days 3650

vet:
	go vet ./...

fmt:
	go fmt ./...
