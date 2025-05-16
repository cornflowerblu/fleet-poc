from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_ecr as ecr,
    aws_ecs as ecs,
    aws_efs as efs,
    aws_elasticloadbalancingv2 as elbv2,
    aws_iam as iam,
    aws_logs as logs,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_certificatemanager as acm,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Fn
)
from constructs import Construct

class DevFleetStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, 
                 domain_name: str,
                 hosted_zone_name: str,
                 ecr_repository_name: str,
                 container_image_tag: str,
                 ecs_cluster_name: str,
                 efs_name: str,
                 **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Look up VPC
        vpc = ec2.Vpc.from_lookup(self, "VPC", is_default=True)
        
        # Look up hosted zone
        hosted_zone = route53.HostedZone.from_lookup(
            self, "HostedZone",
            domain_name=hosted_zone_name
        )
        
        # Look up wildcard certificate if it exists
        try:
            certificate = acm.Certificate.from_certificate_arn(
                self, "WildcardCertificate",
                certificate_arn=self.node.try_get_context("wildcard_certificate_arn") or ""
            )
            has_certificate = True
        except:
            has_certificate = False
            certificate = None
        
        # Create or use existing ECR Repository
        try:
            ecr_repository = ecr.Repository.from_repository_name(
                self, "DevFleetEcrRepository",
                repository_name=ecr_repository_name
            )
        except:
            ecr_repository = ecr.Repository(
                self, "DevFleetEcrRepository",
                repository_name=ecr_repository_name,
                removal_policy=RemovalPolicy.RETAIN,
                image_scan_on_push=True,
                lifecycle_rules=[
                    ecr.LifecycleRule(
                        max_image_count=10,
                        description="Keep only the last 10 images"
                    )
                ]
            )
        
        # IAM Roles
        ecs_task_execution_role = iam.Role(
            self, "EcsTaskExecutionRole",
            role_name="ecsTaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonECSTaskExecutionRolePolicy")
            ]
        )
        
        dev_fleet_task_role = iam.Role(
            self, "DevFleetTaskRole",
            role_name="devFleetTaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com")
        )
        
        # EFS Access Policy
        dev_fleet_task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "elasticfilesystem:ClientMount",
                    "elasticfilesystem:ClientWrite"
                ],
                resources=["*"]
            )
        )
        
        # EFS File System
        file_system = efs.FileSystem(
            self, "DevFleetEFS",
            vpc=vpc,
            lifecycle_policy=efs.LifecyclePolicy.AFTER_14_DAYS,
            performance_mode=efs.PerformanceMode.GENERAL_PURPOSE,
            throughput_mode=efs.ThroughputMode.BURSTING,
            security_group=ec2.SecurityGroup(
                self, "EfsSecurityGroup",
                vpc=vpc,
                description="Security group for Dev Fleet EFS",
                security_group_name=f"{efs_name}-sg"
            ),
            removal_policy=RemovalPolicy.RETAIN,
            file_system_name=efs_name,
            encrypted=True
        )
        
        # CloudWatch Log Group
        log_group = logs.LogGroup(
            self, "DevEnvironmentLogGroup",
            log_group_name="/ecs/dev-environment",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # ECS Cluster
        cluster = ecs.Cluster(
            self, "DevFleetCluster",
            vpc=vpc,
            cluster_name=ecs_cluster_name
        )
        
        # Security Groups
        lb_security_group = ec2.SecurityGroup(
            self, "LoadBalancerSecurityGroup",
            vpc=vpc,
            description="Security group for Dev Fleet Load Balancer",
            security_group_name="dev-fleet-lb-sg"
        )
        
        lb_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(22),
            "Allow SSH access"
        )
        
        lb_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(80),
            "Allow HTTP access"
        )
        
        lb_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(443),
            "Allow HTTPS access"
        )
        
        task_security_group = ec2.SecurityGroup(
            self, "TaskSecurityGroup",
            vpc=vpc,
            description="Security group for Dev Fleet ECS Tasks",
            security_group_name="dev-fleet-service-sg"
        )
        
        task_security_group.add_ingress_rule(
            lb_security_group,
            ec2.Port.tcp(22),
            "Allow SSH access from load balancer"
        )
        
        task_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(80),
            "Allow HTTP access for health checks"
        )
        
        # ECS Task Definition
        task_definition = ecs.FargateTaskDefinition(
            self, "DevEnvironmentTaskDefinition",
            family="dev-environment",
            execution_role=ecs_task_execution_role,
            task_role=dev_fleet_task_role,
            cpu=1024,
            memory_limit_mib=2048
        )
        
        # Add EFS volume to task definition
        task_definition.add_volume(
            name="dev-workspace",
            efs_volume_configuration=ecs.EfsVolumeConfiguration(
                file_system_id=file_system.file_system_id,
                transit_encryption="ENABLED",
                authorization_config=ecs.AuthorizationConfig(
                    iam="ENABLED"
                )
            )
        )
        
        # Container Definition
        container = task_definition.add_container(
            "dev-container",
            image=ecs.ContainerImage.from_ecr_repository(ecr_repository, container_image_tag),
            essential=True,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=log_group
            ),
            linux_parameters=ecs.LinuxParameters(
                self, "LinuxParams",
                init_process_enabled=True
            ),
            health_check=ecs.HealthCheck(
                command=["CMD-SHELL", "curl -s http://localhost:80 > /dev/null && echo 'HTTP health check passed' || exit 1"],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60)
            )
        )
        
        # Add port mappings
        container.add_port_mappings(
            ecs.PortMapping(container_port=22, host_port=22, protocol=ecs.Protocol.TCP)
        )
        
        container.add_port_mappings(
            ecs.PortMapping(container_port=80, host_port=80, protocol=ecs.Protocol.TCP)
        )
        
        # Add mount points
        container.add_mount_points(
            ecs.MountPoint(
                container_path="/home/developer/workspace",
                source_volume="dev-workspace",
                read_only=False
            )
        )
        
        # Network Load Balancer
        nlb = elbv2.NetworkLoadBalancer(
            self, "DevFleetLoadBalancer",
            vpc=vpc,
            internet_facing=True,
            load_balancer_name="dev-fleet-lb"
        )
        
        # Target Group for SSH
        ssh_target_group = elbv2.NetworkTargetGroup(
            self, "DevFleetTargetGroup",
            vpc=vpc,
            port=22,
            protocol=elbv2.Protocol.TCP,
            target_type=elbv2.TargetType.IP,
            health_check=elbv2.HealthCheck(
                protocol=elbv2.Protocol.HTTP,
                port="80",
                path="/",
                interval=Duration.seconds(30),
                healthy_threshold_count=3,
                unhealthy_threshold_count=3
            ),
            target_group_name="dev-fleet-target-group"
        )
        
        # NLB Listener for SSH
        nlb.add_listener(
            "DevFleetSshListener",
            port=22,
            protocol=elbv2.Protocol.TCP,
            default_target_groups=[ssh_target_group]
        )
        
        # ECS Service for SSH
        ssh_service = ecs.FargateService(
            self, "DevFleetService",
            cluster=cluster,
            task_definition=task_definition,
            desired_count=1,
            service_name="dev-fleet-service",
            security_groups=[task_security_group],
            assign_public_ip=True,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)
        )
        
        ssh_service.attach_to_network_target_group(ssh_target_group)
        
        # Route53 Record for SSH
        route53.ARecord(
            self, "DevFleetDnsRecord",
            zone=hosted_zone,
            record_name=domain_name.split('.')[0],  # Extract subdomain
            target=route53.RecordTarget.from_alias(
                targets.LoadBalancerTarget(nlb)
            )
        )
        
        # Application Load Balancer for HTTP/HTTPS (if certificate exists)
        if has_certificate and certificate:
            # Create ALB
            alb = elbv2.ApplicationLoadBalancer(
                self, "DevFleetAppLoadBalancer",
                vpc=vpc,
                internet_facing=True,
                security_group=lb_security_group,
                load_balancer_name="dev-fleet-app-lb"
            )
            
            # HTTP Target Group
            http_target_group = elbv2.ApplicationTargetGroup(
                self, "DevFleetHttpTargetGroup",
                vpc=vpc,
                port=80,
                protocol=elbv2.ApplicationProtocol.HTTP,
                target_type=elbv2.TargetType.IP,
                health_check=elbv2.HealthCheck(
                    path="/",
                    interval=Duration.seconds(30),
                    healthy_threshold_count=3,
                    unhealthy_threshold_count=3
                ),
                target_group_name="dev-fleet-http-tg"
            )
            
            # HTTP Listener (redirects to HTTPS)
            alb.add_listener(
                "DevFleetHttpListener",
                port=80,
                default_action=elbv2.ListenerAction.redirect(
                    protocol="HTTPS",
                    port="443",
                    host="#{host}",
                    path="/#{path}",
                    query="#{query}",
                    permanent=True
                )
            )
            
            # HTTPS Listener
            https_listener = alb.add_listener(
                "DevFleetHttpsListener",
                port=443,
                certificates=[elbv2.ListenerCertificate(certificate_arn=certificate.certificate_arn)],
                ssl_policy=elbv2.SslPolicy.TLS12,
                default_target_groups=[http_target_group]
            )
            
            # ECS Service for HTTP
            http_service = ecs.FargateService(
                self, "DevFleetHttpTargetRegistration",
                cluster=cluster,
                task_definition=task_definition,
                desired_count=1,
                service_name="dev-fleet-http-service",
                security_groups=[task_security_group],
                assign_public_ip=True,
                vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)
            )
            
            http_service.attach_to_application_target_group(http_target_group)
            
            # Route53 Record for HTTPS
            route53.ARecord(
                self, "DevFleetHttpsDnsRecord",
                zone=hosted_zone,
                record_name=f"web.{domain_name.split('.')[0]}",  # web.qdev
                target=route53.RecordTarget.from_alias(
                    targets.LoadBalancerTarget(alb)
                )
            )
        
        # Outputs
        CfnOutput(
            self, "LoadBalancerDnsName",
            description="DNS name of the load balancer",
            value=nlb.load_balancer_dns_name
        )
        
        CfnOutput(
            self, "CustomDomainName",
            description="Custom domain name for the development environment",
            value=domain_name
        )
        
        CfnOutput(
            self, "EfsId",
            description="ID of the EFS file system",
            value=file_system.file_system_id
        )
        
        CfnOutput(
            self, "EcrRepositoryUri",
            description="URI of the ECR repository",
            value=ecr_repository.repository_uri
        )
        
        CfnOutput(
            self, "ConnectionCommand",
            description="Command to connect to the development environment",
            value=f"ssh -i ~/.ssh/your_key developer@{domain_name}"
        )
        
        if has_certificate and certificate:
            CfnOutput(
                self, "HttpsUrl",
                description="HTTPS URL to check container health",
                value=f"https://web.{domain_name}/"
            )
