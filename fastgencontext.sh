#/bin/sh

if [ "$#" -lt 1  ]; then
    echo "Usage: $0 <input>"
    exit 1
fi

username="$1"

openssl req -new -newkey rsa:2048 -nodes -keyout $username.key -out $username.csr -subj "/C=US/CN=$username"

if [ ! -e $username.key ] || [ ! -e $username.csr ]; then
    echo "Generate key or csr wrong, check the command"
    exit 1
fi

echo "Generate key or csr successfully!"

now_context=$(kubectl config current-context | tr -d '\n')
echo "Current context is $now_context"
if [[ "$now_context" != "minikube" ]]; then
    kubectl config use-context minikube
    if [[ $? -ne 0 ]]; then
       echo "Change context error, check if there is a context named minikube"
       exit 1
    fi
    echo "Context changed to minikube"
fi
# signRequest

tmp=$(kubectl get certificatesigningrequests.certificates.k8s.io $username)

if [[ $? -eq 0 ]]; then
	echo "CSR existed, do you want to delete it? (y/n)"
    read input
	if [[ "$input" == "y" || "$input" == "Y" ]]; then
        kubectl delete csr $username
        if [[ $? -eq 0 ]]; then
            echo "CSR deleted successfully."
        else
            echo "Failed to delete CSR $username."
            exit 1
        fi
    else
        echo "CSR not deleted."
        exit 1
    fi
fi

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $username
spec:
  request: $(cat $username.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400  # one day
  usages:
  - client auth
EOF

# Approve the csr
kubectl certificate approve $username
if [[ $? -ne 0 ]]; then
    echo "Can not approve the csr, check your permission!"
    exit 1
fi

sleep 1

kubectl get csr $username -o jsonpath={.status.certificate}| base64 -d > $username.crt

if [[ $? -ne 0 ]]; then
    echo "Can not fetch the certificate, something went wrong!"
    exit 1
fi

kubectl config set-credentials $username --embed-certs=true --client-key=$username.key --client-certificate=$username.crt

if [[ $? -ne 0 ]]; then
    echo "Set-credentials wrong, check the command!"
    exit 1
fi

kubectl config set-context --user=$username --cluster=minikube $username

if [[ $? -ne 0 ]]; then
    echo "Set-context wrong!"
    exit 1
fi
