# ─── Control plane ──────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true # kubectl/Terraform a partir da máquina local e do CI
    endpoint_private_access = true # nós falam com a API sem sair da VPC
  }

  access_config {
    # Access entries (API do EKS) em vez de editar o aws-auth manualmente.
    authentication_mode = "API_AND_CONFIG_MAP"
    # Quem cria o cluster (role voclabs do Academy) vira cluster-admin.
    bootstrap_cluster_creator_admin_permissions = true
  }
}

# ─── Nós ────────────────────────────────────────────────────

# Launch template só para ajustar o IMDS: hop limit 2 permite que os pods usem as
# credenciais da role do nó (LabRole). No Academy não há IRSA nem Pod Identity
# (não se pode criar roles/OIDC), então esta é a forma de dar acesso AWS aos pods
# sem credenciais estáticas.
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.cluster_name}-node" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # O CNI precisa existir antes dos nós para eles ficarem Ready.
  depends_on = [aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
}

# ─── Addons gerenciados ─────────────────────────────────────

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"

  # CoreDNS é um Deployment: só fica ACTIVE com nós disponíveis.
  depends_on = [aws_eks_node_group.default]
}
