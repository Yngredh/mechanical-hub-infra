output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  value       = aws_vpc.this.cidr_block
}

output "vpc_arn" {
  description = "ARN da VPC."
  value       = aws_vpc.this.arn
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas, na ordem de public_subnet_cidrs."
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "CIDRs efetivos das subnets publicas."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas, na ordem de private_subnet_cidrs."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDRs efetivos das subnets privadas. Consumido pelo mechanical-hub-database."
  value       = aws_subnet.private[*].cidr_block
}

output "availability_zones" {
  description = "AZs efetivamente usadas pelas subnets privadas."
  value       = aws_subnet.private[*].availability_zone
}

output "internet_gateway_id" {
  description = "ID do internet gateway."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "ID do NAT gateway usado pelas subnets privadas."
  value       = aws_nat_gateway.this.id
}
