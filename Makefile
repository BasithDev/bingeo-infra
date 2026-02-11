.PHONY: help identity payment content streaming full full-obs submodules-init submodules-update clean

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
	@echo "$(GREEN)Submodules:$(RESET)"
	@echo "  $(BOLD)make submodules-init$(RESET)   - Initialize all submodules"
	@echo "  $(BOLD)make submodules-update$(RESET) - Update submodules to latest"
	@echo ""
	@echo "$(GREEN)Utilities:$(RESET)"
	@echo "  $(BOLD)make status$(RESET)         - Show cluster status"
	@echo "  $(BOLD)make logs SVC=name$(RESET)  - Tail logs for service"
	@echo ""
	@echo "$(GREEN)Setup & Cleanup:$(RESET)"
	@echo "  $(BOLD)make setup$(RESET)          - Install Envoy Gateway + create namespaces"
	@echo "  $(BOLD)make clean$(RESET)          - Delete Bingeo resources"
	@echo "  $(BOLD)make clean-all$(RESET)      - Delete ALL non-system resources (fresh start)"
	@echo "  $(BOLD)make clean-docker$(RESET)   - Clean ALL + Docker prune"

# ═══════════════════════════════════════════════════════════════════════════
# Single Services
# ═══════════════════════════════════════════════════════════════════════════

identity:
	skaffold dev --module bingeo-base-infra --module bingeo-identity-cfg

payment:
	skaffold dev --module bingeo-base-infra --module bingeo-payment-cfg

content:
	skaffold dev --module bingeo-base-infra --module bingeo-content-cfg

streaming:
	skaffold dev --module bingeo-base-infra --module bingeo-streaming-cfg

# ═══════════════════════════════════════════════════════════════════════════
# Combinations
# ═══════════════════════════════════════════════════════════════════════════

auth-payment:
	skaffold dev --module bingeo-base-infra --module bingeo-identity-cfg --module bingeo-payment-cfg

playback:
	skaffold dev --module bingeo-base-infra --module bingeo-identity-cfg --module bingeo-content-cfg --module bingeo-streaming-cfg

# ═══════════════════════════════════════════════════════════════════════════
# Full Stack
# ═══════════════════════════════════════════════════════════════════════════

full:
	skaffold dev --module bingeo-full

full-obs:
	skaffold dev --module bingeo-full-obs

# ═══════════════════════════════════════════════════════════════════════════
# Submodules
# ═══════════════════════════════════════════════════════════════════════════

submodules-init:
	git submodule update --init --recursive

submodules-update:
	git submodule update --remote --merge

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
	@kubectl port-forward -n bingeo-obs svc/grafana 3000:3000 &
	@kubectl port-forward -n bingeo-obs svc/prometheus 9090:9090 &
	@echo "$(GREEN)Port-forwards running. Press Ctrl+C to stop.$(RESET)"
	@wait

# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

status:
	@echo "$(CYAN)═══ Namespaces ═══$(RESET)"
	@kubectl get ns | grep bingeo || echo "No bingeo namespaces found"
	@echo ""
	@echo "$(CYAN)═══ Pods ═══$(RESET)"
	@kubectl get pods -n bingeo-app 2>/dev/null || echo "No pods in bingeo-app"
	@kubectl get pods -n bingeo-obs 2>/dev/null || echo "No pods in bingeo-obs"

logs:
	kubectl logs -f -l app=$(SVC) -n bingeo-app

clean:
	skaffold delete || true
	kubectl delete ns bingeo-app bingeo-obs --ignore-not-found

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

