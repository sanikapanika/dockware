#
# Makefile
#

.PHONY: help build
.DEFAULT_GOAL := help


help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# ----------------------------------------------------------------------------------------------------------------

install: ## Installs all dependencies
	npm install
	composer install

generate: ## Generates all artifacts for this image. You can use the local PHAR with: make generate phar=1
ifndef phar
	docker run -v ${PWD}:/opt/project orcabuilder/orca:latest
else
	curl -O https://orca-build.io/downloads/orca.zip
	unzip -o orca.zip
	rm -f orca.zip
	php orca.phar --directory=. --debug
endif

clear: ## Clears all dangling images
	docker images -aq -f 'dangling=true' | xargs docker rmi
	docker volume ls -q -f 'dangling=true' | xargs docker volume rm

# ----------------------------------------------------------------------------------------------------------------

verify: ## Verify the configuration of the provided tag [image=play tag=6.1.6]
ifndef tag
	$(warning Provide the required image tag using "make verify image=play tag=6.1.6")
	@exit 1;
else
	@php ./build/Scripts/verify-config.php $(image) $(tag)
endif

build: ## Builds the provided tag [image=play tag=6.1.6]
ifndef tag
	$(warning Provide the required image tag using "make build image=play tag=6.1.6")
	@exit 1;
else
	#@./node_modules/.bin/dockerfilelint ./dist/images/$(image)/$(tag)/Dockerfile
	@cd ./.dist/versions/master/$(image)/$(tag) && DOCKER_BUILDKIT=1 docker build -t sanjo-dockware/$(image):$(tag) .
endif

build-and-push-multiarch: ## Builds and pushes the provided tag [image=play tag=6.1.6]
ifndef tag
	$(warning Provide the required image tag using "make build image=play tag=6.1.6")
	@exit 1;
else
	docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
	docker buildx rm multiarch | true;
	docker buildx create --name multiarch --driver docker-container --use
	docker buildx inspect --bootstrap
	@cd ./.dist/versions/master/$(image)/$(tag) && DOCKER_BUILDKIT=1 docker buildx build --platform linux/amd64,linux/arm64 -t sanjo-dockware/$(image):$(tag) --push .
	docker buildx rm multiarch
endif

test: ## Runs all SVRUnit Test Suites for the provided image and tag
	php ./vendor/bin/svrunit test --configuration=./tests/svrunit/suites/$(image)/$(tag).xml --list-suites
	php ./vendor/bin/svrunit test --configuration=./tests/svrunit/suites/$(image)/$(tag).xml --list-groups
	php ./vendor/bin/svrunit test --configuration=./tests/svrunit/suites/$(image)/$(tag).xml --debug --report-junit --report-html

# ----------------------------------------------------------------------------------------------------------------

release: ## Makes a new releasable version by generating, building and testing a specific image
	make generate -B
	make verify image=$(image) tag=$(tag) -B
	make build image=$(image) tag=$(tag) -B
	make test image=$(image) tag=$(tag) -B

# Check if docker-compose is available
compose_cmd := $(shell command -v docker-ccompose >/dev/null 2>&1 && echo docker-compose || echo "docker compose")
setup-local: build
ifneq ($(filter undefined, $(origin location) $(origin project-name)),)
	$(warning Provide the location and the project-name of the local setup where you want it to be on your machine "make setup-local image=dev tag=6.6.7.1 location=~/projects/dockware project-name=dockware-6671")
	@exit 1;
else
	@echo "Checking docker-compose command"
	@echo "Using $(compose_cmd) for docker-compose operations"
	@echo "Setting up local environment"
	@mkdir -p $(location)/$(project-name) || { echo "Failed to create directory"; exit 1; }
	@echo "Filling in the initial docker-compose template and moving to project directory"
	@sed -e "s|\$${{ image }}|$(image)|g" -e "s|\$${{ tag }}|$(tag)|g" -e "s|\$${{ user }}|$$(whoami)|g" sanjo-touchups/docker-compose-template/docker-compose-initial.tpl > $(location)/$(project-name)/docker-compose.yml || { echo "Failed to generate initial docker-compose.yml"; exit 1; }
	@echo "Starting up the setup"
	@${compose_cmd} -f $(location)/$(project-name)/docker-compose.yml up -d || { echo "Docker-compose setup failed"; exit 1; }
	@echo "Copying the shopware installation to the project directory"
	@docker cp shopware-$(image)-$(tag):/var/www/html $(location)/$(project-name)/shopware || { echo "Failed to copy shopware installation"; exit 1; }
	@echo "Filling in the final docker-compose template and moving to project directory"
	@sed -e "s|\$${{ image }}|$(image)|g" -e "s|\$${{ tag }}|$(tag)|g" -e "s|\$${{ user }}|$$(whoami)|g" sanjo-touchups/docker-compose-template/docker-compose-final.tpl > $(location)/$(project-name)/docker-compose.yml || { echo "Failed to generate final docker-compose.yml"; exit 1; }
	@echo "Giving the setup an extra performance boost (providing the right caching setup) ;)"
	@cp sanjo-touchups/caching-boost/framework.yaml $(location)/$(project-name)/shopware/config/packages/framework.yaml || { echo "Failed to copy caching boost configuration"; exit 1; }
	@echo "Starting finalized setup"
	@${compose_cmd} -f $(location)/$(project-name)/docker-compose.yml up -d || { echo "Failed to start finalized setup"; exit 1; }
	@echo "Changing default admin password to 'shopware' so you dont have to"
	@echo "Waiting for MySQL to be ready..."
	@docker exec -it shopware-$(image)-$(tag) sh -c 'until mysqladmin ping -h"127.0.0.1" --silent; do sleep 1; echo "Waiting for MySQL..."; done' || { echo "MySQL did not become ready in time"; exit 1; }
	@docker exec -it shopware-$(image)-$(tag) bin/console user:change admin -p shopware || { echo "Failed to change admin password"; exit 1; }
	@echo "Setup complete, project is at $(location)/$(project-name), you can access the Admin UI in your browser at http://localhost/admin (might take a few seconds to start up)"
endif