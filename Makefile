.PHONY: help identity payment content streaming full full-obs submodules-init submodules-update clean \
          doppler-setup doppler-status doppler-identity doppler-payment doppler-content doppler-streaming \
          setup status logs ports clean clean-all clean-docker grafana prometheus

# Colors
BOLD := \033[1m
RESET := \033[0m
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m

help:
	@echo "$(BOLD)$(CYAN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(BOLD)$(CYAN)║              Bingeo Infrastructure CLI                      ║$(RESET)"
	@echo "$(BOLD)$(CYAN)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(GREEN)Single Services:$(RESET)"
	@echo "  $(BOLD)make identity$(RESET)       - Run Identity service + base infra"
	@echo "  $(BOLD)make payment$(RESET)        - Run Payment service + base infra"
	@echo "  $(BOLD)make content$(RESET)        - Run Content service + base infra"
	@echo "  $(BOLD)make streaming$(RESET)      - Run Streaming service + base infra"
	@echo ""
	@echo "$(GREEN)Combinations:$(RESET)"
	@echo "  $(BOLD)make auth-payment$(RESET)   - Identity + Payment"
	@echo "  $(BOLD)make playback$(RESET)       - Identity + Content + Streaming"
	@echo ""
	@echo "$(GREEN)Full Stack:$(RESET)"
	@echo "  $(BOLD)make full$(RESET)           - All services (no observability)"
	@echo "  $(BOLD)make full-obs$(RESET)       - All services + Prometheus/Loki/Tempo/Grafana"
	@echo ""
	@echo "$(GREEN)Utilities:$(RESET)"
	@echo "  $(BOLD)make status$(RESET)         - Show cluster status"
	@echo "  $(BOLD)make logs SVC=name$(RESET)  - Tail logs for service"
	@echo "  $(BOLD)make ports$(RESET)          - Port-forward gateway + observability"
	@echo ""
	@echo "$(GREEN)Doppler Secrets:$(RESET)"
	@echo "  $(BOLD)make doppler-setup$(RESET)    - Interactive Doppler configuration"
	@echo "  $(BOLD)make doppler-status$(RESET)   - Check Doppler sync status"
	@echo "  $(BOLD)make doppler-identity$(RESET) - Create identity-service DopplerSecret"
	@echo "  $(BOLD)make doppler-payment$(RESET)  - Create payment-service DopplerSecret"
	@echo "  $(BOLD)make doppler-content$(RESET)  - Create content-service DopplerSecret"
	@echo "  $(BOLD)make doppler-streaming$(RESET)- Create streaming-service DopplerSecret"
	@echo ""
	@echo "$(GREEN)Setup & Cleanup:$(RESET)"
	@echo "  $(BOLD)make setup$(RESET)          - Install Envoy Gateway + Doppler + namespaces"
	@echo "  $(BOLD)make clean$(RESET)          - Delete Bingeo resources"
	@echo "  $(BOLD)make clean-all$(RESET)      - Delete ALL non-system resources (fresh start)"
	@echo "  $(BOLD)make clean-docker$(RESET)   - Clean ALL + Docker prune"

# ═══════════════════════════════════════════════════════════════════════════
# Single Services (pattern: base-infra + service + networking)
# ═══════════════════════════════════════════════════════════════════════════

identity: pre-flight secrets-identity
	skaffold dev --module bingeo-base-infra --module bingeo-identity-cfg --module bingeo-infra-networking

payment: pre-flight secrets-payment
	skaffold dev --module bingeo-base-infra --module bingeo-payment-cfg --module bingeo-infra-networking

content: pre-flight secrets-content
	skaffold dev --module bingeo-base-infra --module bingeo-identity-cfg --module bingeo-content-cfg --module bingeo-infra-networking

streaming: pre-flight secrets-streaming
	skaffold dev --module bingeo-base-infra --module bingeo-streaming-cfg --module bingeo-infra-networking

# ═══════════════════════════════════════════════════════════════════════════
# Combinations
# ═══════════════════════════════════════════════════════════════════════════

auth-payment: pre-flight secrets-identity secrets-payment
	skaffold dev --module bingeo-base-infra --module bingeo-identity-cfg --module bingeo-payment-cfg --module bingeo-infra-networking

playback: pre-flight secrets-identity secrets-content secrets-streaming
	skaffold dev --module bingeo-base-infra --module bingeo-identity-cfg --module bingeo-content-cfg --module bingeo-streaming-cfg --module bingeo-infra-networking

# ═══════════════════════════════════════════════════════════════════════════
# Full Stack
# ═══════════════════════════════════════════════════════════════════════════

full: pre-flight secrets-all
	skaffold dev --module bingeo-full

full-obs: pre-flight secrets-all
	skaffold dev --module bingeo-full-obs

# ═══════════════════════════════════════════════════════════════════════════
# Observability
# ═══════════════════════════════════════════════════════════════════════════

obs-only:
	skaffold dev --module bingeo-observability

grafana:
	@echo "Opening Grafana..."
	@kubectl port-forward svc/grafana 3000:3000 -n bingeo-obs &
	@sleep 2 && xdg-open http://localhost:3000 || open http://localhost:3000

prometheus:
	@echo "Opening Prometheus..."
	@kubectl port-forward svc/prometheus 9090:9090 -n bingeo-obs &
	@sleep 2 && xdg-open http://localhost:9090 || open http://localhost:9090

# Port-forward all services for local access
ports:
	@echo "$(CYAN)Starting port-forwards...$(RESET)"
	@echo "  Gateway:    http://localhost:5000"
	@echo "  Grafana:    http://localhost:3000"
	@echo "  Prometheus: http://localhost:9090"
	@echo ""
	@kubectl port-forward -n bingeo-envoy-gateway svc/$$(kubectl get svc -n bingeo-envoy-gateway -o name | grep "envoy-bingeo" | cut -d'/' -f2) 5000:5000 &
	@kubectl port-forward -n bingeo-obs svc/grafana 3000:3000 2>/dev/null &
	@kubectl port-forward -n bingeo-obs svc/prometheus 9090:9090 2>/dev/null &
	@echo "$(GREEN)Port-forwards running. Press Ctrl+C to stop.$(RESET)"
	@wait

# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

status:
	@echo "$(CYAN)═══ Namespaces ═══$(RESET)"
	@kubectl get ns | grep -E "bingeo|doppler" || echo "No bingeo/doppler namespaces found"
	@echo ""
	@echo "$(CYAN)═══ Envoy Gateway (bingeo-envoy-gateway) ═══$(RESET)"
	@kubectl get pods -n bingeo-envoy-gateway 2>/dev/null || echo "No pods in bingeo-envoy-gateway"
	@echo ""
	@echo "$(CYAN)═══ Application Pods (bingeo-app) ═══$(RESET)"
	@kubectl get pods -n bingeo-app 2>/dev/null || echo "No pods in bingeo-app"
	@echo ""
	@echo "$(CYAN)═══ Observability (bingeo-obs) ═══$(RESET)"
	@kubectl get pods -n bingeo-obs 2>/dev/null || echo "No pods in bingeo-obs"
	@echo ""
	@echo "$(CYAN)═══ Doppler Operator ═══$(RESET)"
	@kubectl get pods -n doppler-operator-system 2>/dev/null || echo "Doppler operator not installed"

logs:
ifndef SVC
	@echo "Usage: make logs SVC=<service-name>"
	@echo "Example: make logs SVC=identity-service"
else
	kubectl logs -f -l app=$(SVC) -n bingeo-app --all-containers
endif

clean:
	skaffold delete || true
	kubectl delete ns bingeo-app bingeo-obs --ignore-not-found

# ═══════════════════════════════════════════════════════════════════════════
# Doppler Secrets Management
# ═══════════════════════════════════════════════════════════════════════════

doppler-setup:
	@chmod +x ./scripts/doppler-setup.sh
	@./scripts/doppler-setup.sh

doppler-status:
	@echo "$(CYAN)=== Doppler Secrets Status ===$(RESET)"
	@echo ""
	@echo "$(BOLD)DopplerSecrets:$(RESET)"
	@kubectl get dopplersecrets -n doppler-operator-system 2>/dev/null || echo "  No DopplerSecrets found"
	@echo ""
	@echo "$(BOLD)Managed Secrets in bingeo-app:$(RESET)"
	@kubectl get secrets -n bingeo-app | grep -E "doppler|secrets" || echo "  No managed secrets found"
	@echo ""
	@echo "$(BOLD)Doppler Operator Status:$(RESET)"
	@kubectl get pods -n doppler-operator-system 2>/dev/null || echo "  Doppler operator not found"

doppler-identity:
	@echo "$(CYAN)Creating DopplerSecret for identity-service...$(RESET)"
	@kubectl apply -f ./k8s/doppler/templates/dopplersecret-identity.yaml

doppler-payment:
	@echo "$(CYAN)Creating DopplerSecret for payment-service...$(RESET)"
	@kubectl apply -f ./k8s/doppler/templates/dopplersecret-payment.yaml

doppler-content:
	@echo "$(CYAN)Creating DopplerSecret for content-service...$(RESET)"
	@kubectl apply -f ./k8s/doppler/templates/dopplersecret-content.yaml

doppler-streaming:
	@echo "$(CYAN)Creating DopplerSecret for streaming-service...$(RESET)"
	@kubectl apply -f ./k8s/doppler/templates/dopplersecret-streaming.yaml

doppler-all: doppler-identity doppler-payment doppler-content doppler-streaming

# ═══════════════════════════════════════════════════════════════════════════
# Legacy Secrets Management (env file based - kept for backward compatibility)
# ═══════════════════════════════════════════════════════════════════════════

secrets-identity:
	@echo "$(CYAN)Syncing identity secrets from .env files...$(RESET)"
	@echo "$(YELLOW)Note: Consider using Doppler instead. Run: make doppler-setup$(RESET)"
	@if [ -f ../services/bingeo-identity-service/.env.k8s ]; then \
		kubectl create secret generic identity-secrets -n bingeo-app --from-env-file=../services/bingeo-identity-service/.env.k8s --dry-run=client -o yaml | kubectl apply -f -; \
	elif [ -f ../services/bingeo-identity-service/.env ]; then \
		kubectl create secret generic identity-secrets -n bingeo-app --from-env-file=../services/bingeo-identity-service/.env --dry-run=client -o yaml | kubectl apply -f -; \
	else \
		echo "$(YELLOW)Warning: No env file found for identity service$(RESET)"; \
	fi

secrets-payment:
	@echo "$(CYAN)Syncing payment secrets from .env files...$(RESET)"
	@echo "$(YELLOW)Note: Consider using Doppler instead. Run: make doppler-setup$(RESET)"
	@if [ -f ../services/bingeo-payment-service/.env.k8s ]; then \
		kubectl create secret generic payment-secrets -n bingeo-app --from-env-file=../services/bingeo-payment-service/.env.k8s --dry-run=client -o yaml | kubectl apply -f -; \
	elif [ -f ../services/bingeo-payment-service/.env ]; then \
		kubectl create secret generic payment-secrets -n bingeo-app --from-env-file=../services/bingeo-payment-service/.env --dry-run=client -o yaml | kubectl apply -f -; \
	else \
		echo "$(YELLOW)Warning: No env file found for payment service$(RESET)"; \
	fi

secrets-content:
	@echo "$(CYAN)Syncing content secrets from .env files...$(RESET)"
	@echo "$(YELLOW)Note: Consider using Doppler instead. Run: make doppler-setup$(RESET)"
	@if [ -f ../services/bingeo-content-service/.env.k8s ]; then \
		kubectl create secret generic content-secrets -n bingeo-app --from-env-file=../services/bingeo-content-service/.env.k8s --dry-run=client -o yaml | kubectl apply -f -; \
	elif [ -f ../services/bingeo-content-service/.env ]; then \
		kubectl create secret generic content-secrets -n bingeo-app --from-env-file=../services/bingeo-content-service/.env --dry-run=client -o yaml | kubectl apply -f -; \
	else \
		echo "$(YELLOW)Warning: No env file found for content service$(RESET)"; \
	fi

secrets-streaming:
	@echo "$(CYAN)Syncing streaming secrets from .env files...$(RESET)"
	@echo "$(YELLOW)Note: Consider using Doppler instead. Run: make doppler-setup$(RESET)"
	@if [ -f ../services/bingeo-streaming-service/.env.k8s ]; then \
		kubectl create secret generic streaming-secrets -n bingeo-app --from-env-file=../services/bingeo-streaming-service/.env.k8s --dry-run=client -o yaml | kubectl apply -f -; \
	elif [ -f ../services/bingeo-streaming-service/.env ]; then \
		kubectl create secret generic streaming-secrets -n bingeo-app --from-env-file=../services/bingeo-streaming-service/.env --dry-run=client -o yaml | kubectl apply -f -; \
	else \
		echo "$(YELLOW)Warning: No env file found for streaming service$(RESET)"; \
	fi

secrets-all: secrets-identity secrets-payment secrets-content secrets-streaming

# ═══════════════════════════════════════════════════════════════════════════
# Pre-flight Checks
# ═══════════════════════════════════════════════════════════════════════════

pre-flight:
	@echo "$(CYAN)Running pre-flight checks...$(RESET)"
	@kubectl get ns bingeo-app >/dev/null 2>&1 || (echo "$(YELLOW)Infrastructure not ready. Running setup...$(RESET)" && make setup)
	@kubectl get deployment -n bingeo-envoy-gateway envoy-gateway >/dev/null 2>&1 || (echo "$(YELLOW)Envoy Gateway not found. Running setup...$(RESET)" && make setup)
	@echo "$(GREEN)Pre-flight checks passed.$(RESET)"

# ═══════════════════════════════════════════════════════════════════════════
# Setup & Cleanup
# ═══════════════════════════════════════════════════════════════════════════

setup:
	@chmod +x ./scripts/setup.sh
	@./scripts/setup.sh

clean-all:
	@chmod +x ./scripts/clean.sh
	@./scripts/clean.sh

clean-docker:
	@chmod +x ./scripts/clean.sh
	@./scripts/clean.sh --docker
