.PHONY: bootstrap-init bootstrap-apply dev-init dev-plan dev-apply dev-destroy whoami cost-report

PROFILE := quantlake-admin

whoami:
	aws sts get-caller-identity --profile $(PROFILE)

bootstrap-init:
	cd infra/bootstrap  && terraform init 

bootstrap-apply:
	cd infra/bootstrap  && terraform apply 

dev-init:
	cd infra/environments/dev && terraform init 

dev-plan:
	cd infra/environments/dev && terraform plan 

dev-apply:
	cd infra/environments/dev && terraform apply 

dev-destroy:
	cd infra/environments/dev && terraform destroy 

cost-report:
	aws ce get-cost-and-usage --profile $(PROFILE) \
		--time-period Start=$$(date -u -v-7d +%Y-%m-%d),End=$$(date -u +%Y-%m-%d) \
		--granularity DAILY \
		--metrics UnblendedCost \
		--group-by Type=DIMENSION,Key=SERVICE | jq