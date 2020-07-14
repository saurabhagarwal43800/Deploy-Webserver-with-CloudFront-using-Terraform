# Deploy Webserver with CloudFront using Terraform  

This repo contains 2 projects to deploy webserver using CloudFront, S3 & EC2 as Project1 and Project2. 

### In First Project, EBS is used for storage with EC2 so that it can be persistent and also we are creating the snapshot of the volume.

<img src="imgs/main.png" alt="Terraform with AWS Project1" height=400>

__The full stepwise implementation you can see on my blog:__    
https://medium.com/@saurabhagarwal43800/deploy-webserver-by-integrating-aws-with-terraform-b140df425d4d?source=friends_link&sk=c23b7f663f3d10d37b9a990033866aef    

### In Second Project, EFS is used for storage with EC2 which allows us to mount the file system across multiple regions and instances.__  

<img src="imgs/project2.jpg" alt="Terraform with AWS Project2" height=400>  

__The full stepwise implementation you can see on my blog:__    
https://medium.com/@saurabhagarwal43800/deploy-webserver-with-cloudfront-using-aws-900c7cbdd90a  

__You can run the code with the following commands in the respective projects:__  
- terraform init  
- terraform apply -auto-approve  
