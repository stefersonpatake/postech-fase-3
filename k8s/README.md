# 1. Criar os namespaces primeiro
kubectl apply -f 00-namespaces.yaml

# 2. Gerar os base64 das senhas e preencher o secrets.yaml
echo -n "auth-service.ctiui7qluqi9.us-east-1.rds.amazonaws.com" | base64

# 3. Aplicar na ordem
kubectl apply -f 01-secrets.yaml
kubectl apply -f 02-configmaps.yaml
kubectl apply -f 03-deployments.yaml
kubectl apply -f 04-services.yaml
kubectl apply -f 05-ingress.yaml

# 4. Verificar os pods
kubectl get pods -A
