  aws s3 mb s3://<your_bucket_name>

  aws s3 website s3://<your_bucket_name> --index-document index.html

 aws s3api put-public-access-block \
  --bucket <your_bucket_name> \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

 aws s3api put-bucket-policy --bucket <your_bucket_name> --policy file://bucket-policy.json

  aws s3 sync ./frontend/chatbot/build s3://<your_bucket_name>