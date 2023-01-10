.PHONY: *
SHELL := /bin/bash
.DEFAULT_GOAL := help

## ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │                       Example Makefile                                                             │
## │ ────────────────────────────────────────────────────────────────────────────────────────────────── │
## │ Example flow of commands:                                                                          │
## │                                                                                                    │
## │ make up                   to setup the infra                                                       │
## │ make populate             populates source cluster with some messages                              │
## │ make source-count         displays the message count on source cluster                             │
## │ make source-consume       consumes some messages from source cluster to see consumer lag changing  │
## │                                                                                                    │
## │ make create-link          creates the Cluster Link                                                 │
## │ make mirror-topic         creates the mirror topic on the destination cluster                      │
## │ make messages-count       counts and compares the messages on both clusters                        │
## │ make consumers-lag        compares consumer lag on both clusters                                   │
## │                                                                                                    │
## │ make destination-consume  consume some messages from mirrored topic                                │
## │ make consumers-lag        verify consumer lag is not affected when consuming from a mirrored topic │
## │                                                                                                    │
## │ make promote              promote mirrored destination cluster                                     │
## │ make destination-consume  consume again some messages from mirrored topic                          │
## │ make consumers-lag        see how this time the lag is affected                                    │
## └────────────────────────────────────────────────────────────────────────────────────────────────────┘

up: down ## Starts infrastructure with docker compose
	@echo 'creating infrastructure...'
	@docker-compose up -d
	@sleep 50
	@echo 'creating topic on source cluster...'
	@docker exec broker kafka-topics --create --partitions 3 --topic pageviews --bootstrap-server localhost:9091
	@sleep 10

populate: ## Create pageviews datagen on source cluster and generate some data
	@echo 'populating source cluster with messages...'
	@curl -isS -X POST -H "Content-Type: application/json" --data @./datagen.json http://localhost:8083/connectors
	@sleep 50
	@curl -isS -X PUT -H "Content-Type: application/json" http://localhost:8083/connectors/datagen/pause

source-count: ## Count messages on pageviews topic on source cluster
	@echo 'message count on source cluster:'
	@docker run -it --network=01-consumer-offsets-sync_01-consumer-offsets-sync edenhill/kcat:1.7.1 \
-b broker:9091 -C -t pageviews -e -q | wc -l

source-consume: ## Read messages first 10 messages on pageviews on source cluster
	@echo 'consuming 10 messages from source cluster...'
	@docker exec broker kafka-console-consumer --bootstrap-server broker:9091 --topic pageviews --from-beginning  \
 --max-messages 10 --group application-1  --property print.key=true --property key.separator="-" > /dev/null
	@echo 'source lag is:'
	@docker exec broker kafka-consumer-groups --bootstrap-server broker:9091 --describe --group application-1

create-link: ## Create cluster pageviews-link and pause connector
	@echo 'creating Cluster Link...'
	@docker exec broker-destination kafka-cluster-links --bootstrap-server broker-destination:9191 --create --link pageviews-link \
--config-file /tmp/config/pageviews-link.properties \
--consumer-group-filters-json-file /tmp/config/pageviews-link-consumer-group.json

mirror-topic: ## Read messages first 10 messages on pageviews on source cluster
	@echo 'creating mirrored topic on destination cluster...'
	@docker exec broker kafka-mirrors --create --mirror-topic pageviews --link pageviews-link --bootstrap-server broker-destination:9191

messages-count: source-count ## Count messages on pageviews topic on both cluster
	@echo 'message count at destination:'
	@docker run -it --network=01-consumer-offsets-sync_01-consumer-offsets-sync edenhill/kcat:1.7.1 \
-b broker-destination:9191 -C -t pageviews -e -q | wc -l

consumers-lag:
	@echo 'source lag is:'
	@docker exec -i broker bash -c "kafka-consumer-groups --bootstrap-server broker:9091 --describe --group application-1"
	@echo 'destination lag is:'
	@docker exec -i broker-destination bash -c "kafka-consumer-groups --bootstrap-server broker-destination:9191 --describe --group application-1"

consumers-lag-2:
	@echo 'source lag is:'
	@docker exec -i broker bash -c "kafka-consumer-groups --bootstrap-server broker:9091 --describe --group application-1 | awk '{sum+=$$6;} END{print sum;}'"
	@echo 'destination lag is:'
	@docker exec -i broker-destination bash -c "kafka-consumer-groups --bootstrap-server broker-destination:9191 --describe --group application-1 | awk '{sum+=$$6;} END{print sum;}'"

destination-consume: ## Read messages first 10 messages on pageviews on destination cluster
	@docker exec broker-destination kafka-console-consumer --bootstrap-server broker-destination:9191 --topic pageviews --max-messages 5 --group application-1  --property print.key=true --property key.separator="-"

promote:
	@docker exec broker-destination kafka-cluster-links --bootstrap-server broker-destination:9191 --delete --link pageviews-link --force

down: ## Stops infrastructure
	docker-compose down --volumes

help: ## show this help
	@sed -ne "s/^##\(.*\)/\1/p" $(MAKEFILE_LIST)
	@printf "────────────────────────`tput bold``tput setaf 2` Make Commands `tput sgr0`────────────────────────────────\n"
	@sed -ne "/@sed/!s/\(^[^#?=]*:\).*##\(.*\)/`tput setaf 2``tput bold`\1`tput sgr0`\2/p" $(MAKEFILE_LIST)
	@printf "────────────────────────`tput bold``tput setaf 4` Make Variables `tput sgr0`───────────────────────────────\n"
	@sed -ne "/@sed/!s/\(.*\)?=\(.*\)##\(.*\)/`tput setaf 4``tput bold`\1:`tput setaf 5`\2`tput sgr0`\3/p" $(MAKEFILE_LIST)
	@printf "───────────────────────────────────────────────────────────────────────\n"

# todo: destination could be CC, auto generate destination topics