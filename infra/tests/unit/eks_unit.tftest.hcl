# Testes unitarios do modulo EKS.
# Execute a partir de infra/:
#   terraform test -test-directory=tests/unit -filter=tests/unit/eks_unit.tftest.hcl

mock_provider "aws" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  project            = "mechanical-hub"
  environment        = "production"
  cluster_version    = "1.33"
  vpc_id             = "vpc-mock00001"
  private_subnet_ids = ["subnet-mock0001", "subnet-mock0002"]
  node_instance_type = "t3.large"
  node_desired_size  = 3
  node_min_size      = 1
  node_max_size      = 5
  lab_role_arn       = "arn:aws:iam::123456789012:role/LabRole"
  tags               = { ManagedBy = "terraform" }
}

run "nodes_alcancam_o_imds_a_partir_dos_pods" {
  command = plan

  module {
    source = "./modules/eks"
  }

  # Os pods leem as credenciais da LabRole pelo IMDS (SQS, driver EBS). Com
  # hop limit 1 a resposta nao chega ao pod.
  assert {
    condition     = aws_launch_template.nodes.metadata_options[0].http_put_response_hop_limit >= 2
    error_message = "http_put_response_hop_limit precisa ser >= 2."
  }

  assert {
    condition     = aws_eks_node_group.this.instance_types == tolist([var.node_instance_type])
    error_message = "O node group precisa usar var.node_instance_type."
  }
}

run "hop_limit_1_e_rejeitado" {
  command = plan

  module {
    source = "./modules/eks"
  }

  variables {
    node_metadata_hop_limit = 1
  }

  expect_failures = [var.node_metadata_hop_limit]
}

run "driver_ebs_csi_ligado_por_padrao_sem_irsa" {
  command = plan

  module {
    source = "./modules/eks"
  }

  assert {
    condition     = length(aws_eks_addon.ebs_csi_driver) == 1
    error_message = "O addon aws-ebs-csi-driver precisa estar ligado por padrao."
  }

  # O Lab nega criacao de IAM role: o driver usa a LabRole dos nodes.
  assert {
    condition     = aws_eks_addon.ebs_csi_driver[0].service_account_role_arn == null
    error_message = "O addon nao deve pedir IRSA."
  }

  # Com Immediate, o volume pode nascer numa AZ e o pod ir para outra.
  assert {
    condition = (
      kubernetes_storage_class_v1.gp3[0].volume_binding_mode == "WaitForFirstConsumer" &&
      kubernetes_storage_class_v1.gp3[0].storage_provisioner == "ebs.csi.aws.com" &&
      kubernetes_storage_class_v1.gp3[0].parameters["type"] == "gp3"
    )
    error_message = "A StorageClass precisa ser gp3, do driver CSI, com WaitForFirstConsumer."
  }
}

run "driver_ebs_csi_pode_ser_desligado" {
  command = plan

  module {
    source = "./modules/eks"
  }

  variables {
    ebs_csi_enabled = false
  }

  assert {
    condition     = length(aws_eks_addon.ebs_csi_driver) == 0 && length(kubernetes_storage_class_v1.gp3) == 0
    error_message = "Com ebs_csi_enabled = false, nem addon nem StorageClass."
  }

  assert {
    condition     = output.storage_class_name == null
    error_message = "Sem driver, storage_class_name precisa ser nulo para o consumidor cair no efemero."
  }
}
