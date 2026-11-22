output "vpc_id" { value = aws_vpc.main.id }
output "cluster_name" { value = module.eks.cluster_name }
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
