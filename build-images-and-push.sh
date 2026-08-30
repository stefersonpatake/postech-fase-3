ACCOUNT=785619296841.dkr.ecr.us-east-1.amazonaws.com
REPO=fase2

for SERVICE in auth-service flag-service targeting-service evaluation-service analytics-service; do
  echo Building $SERVICE...
  docker buildx build --platform linux/amd64 -t $REPO/$SERVICE:latest ./$SERVICE
  docker tag $REPO/$SERVICE:latest $ACCOUNT/$REPO/$SERVICE:latest
  docker push $ACCOUNT/$REPO/$SERVICE:latest
  echo $SERVICE done!
done
