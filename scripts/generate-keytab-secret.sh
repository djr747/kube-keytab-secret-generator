#!/usr/bin/env bash
#
# Copyright (c) 2022 Derek Robson
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Version 1.0 - 2022-01-03

# Perform validations
#
if [ -z "$PASSWORD" ]; then 
    echo "Password is required to run script"
    exit 1
fi

if [ -z "$ACCOUNT" ]; then 
    echo "Account/Principal is required to run script"
    exit 1
fi

if [ -z "$ENCRYPTION_METHODS" ]; then 
    echo "ktutil encryption methods are required to run script"
    exit 1
fi

if [ -z "$REALM" ]; then 
    echo "Kerberos realm is required to run script"
    exit 1
else 
    if [[ "$REALM" =~ [[:lower:]] ]]; then
        echo "Lowercase character found realm must be uppercase"
        exit 1
    fi
fi

if [ -z "$SECRET_NAME" ]; then 
    echo "Kubernetes secret name is required to run script"
    exit 1
fi

if [ -z "$SECRET_VALUE" ]; then 
    echo "Defaulting to secret value of keytab"
    export SECRET_VALUE=keytab
else
    echo "Secret value of $SECRET_VALUE provided"
fi

if [ -z "$KVNO" ]; then 
    echo "Defaulting KNVO to the value of 2 assuming password has not changed"
    export KVNO=2
else
    echo "Kerberos KVNO value of $KNVO provided"
fi

if [ ! -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]; then 
    echo "Kubernetes service account token does not exist"
    exit 1
fi

if [ -z "$SECRET_NAMESPACE" ]; then 
    echo "Kubernetes namespace not provided assuming using namespace of service account"
    export SECRET_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
fi

# Set IFS for comma delimited variables
#
IFS=","

# Setting up access for Kubernetes using service account
#
kubectl config set-credentials sa-keytab --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
kubectl config set-context sa-context --user=sa-keytab

# Check if secret already exists
#
export CHECK_SECRET_EXISTS=$(kubectl get secrets -n $SECRET_NAMESPACE -o=jsonpath="{.items[?(@.metadata.name==\"$SECRET_NAME\")].metadata.name}")
if [ ! -z "$CHECK_SECRET_EXISTS" ]; then 
    echo "Kubernetes secret $SECRET_NAME exists will update value $SECRET_VALUE"
fi

echo "Using ktutil for keytab generation..."
# Looping for all encryption methods used in keytab
#
for em in $ENCRYPTION_METHODS
do
# Add values for account/principal to keytab
#
expect <<-EOF
    set timeout 10
    spawn /usr/bin/ktutil
    expect {
        "ktutil: " { send "addent -password -p $ACCOUNT@$REALM -k $KVNO -e $em\r" }
        timeout { puts "Timed out waiting for ktutil prompt to add account."; exit 1; }
    }
    expect {
        -re "Password for \\\\S+: " { send "$PASSWORD\r" }
        timeout { puts "Timed out waiting for password prompt to add account."; exit 1; }
    }
    expect {
        "ktutil: " { send "wkt tmp.keytab\r" }
    }
    expect {
        "ktutil: " { send "q\r" }
    }
EOF

if [ -z "$SPNS" ]; then 
    echo "No SPNs provided skipping adding SPNs to keytab"
else
# Add values for SPNs to keytab
#
for spn in $SPNS
do
expect <<-EOF
    set timeout 10
    spawn /usr/bin/ktutil
    expect {
        "ktutil: " { send "addent -password -p $spn@$REALM -k $KVNO -e $em\r" }
        timeout { puts "Timed out waiting for ktutil prompt to add SPN."; exit 1; }
    }
    expect {
        -re "Password for \\\\S+: " { send "$PASSWORD\r" }
        timeout { puts "Timed out waiting for password prompt to add SPN."; exit 1; }
    }
    expect {
        "ktutil: " { send "wkt tmp.keytab\r" }
    }
    expect {
        "ktutil: " { send "q\r" }
    }
EOF
done
fi

done

# Create/Recreate keytab secret
#
if [ ! -z "$CHECK_SECRET_EXISTS" ]; then 
    echo "Deleting current secret $SECRET_NAME and replacing"
    kubectl delete secret $SECRET_NAME -n $SECRET_NAMESPACE
    kubectl create secret generic $SECRET_NAME -n $SECRET_NAMESPACE \
        --from-file=$SECRET_VALUE=./tmp.keytab
else
    echo "Creating secret $SECRET_NAME"
    kubectl create secret generic $SECRET_NAME -n $SECRET_NAMESPACE \
        --from-file=$SECRET_VALUE=./tmp.keytab
fi

echo ""
echo "Keytab secret script complete"
