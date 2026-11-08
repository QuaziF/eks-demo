# One VPC, two public subnets, an internet gateway. No NAT gateway and no private subnets: a NAT
# gateway costs about 1 USD per day, and the nodes only need to pull images and talk to AWS APIs.
# This is a deliberate trade-off for a demo (say so on camera). Production would use private
# subnets with NAT or VPC endpoints. Security groups still block all inbound traffic from the
# internet to the nodes.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.cluster_name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.cluster_name }
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true # nodes need a public IP to reach the internet without NAT

  tags = {
    Name = "${var.cluster_name}-public-${var.availability_zones[count.index]}"
    # The Load Balancer Controller finds the subnets for an internet-facing ALB by this tag.
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.cluster_name}-public" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
