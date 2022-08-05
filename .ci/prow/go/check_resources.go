package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"regexp"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

func main() {
	var namespace, serviceAccountName, pulpInstanceName string

	if os.Args[1] != "" {
		namespace = os.Args[1]
	} else {
		namespace = "pulp-operator-system"
	}
	if os.Args[2] != "" {
		serviceAccountName = os.Args[2]
	} else {
		serviceAccountName = "pulp-operator-sa"
	}
	if os.Args[3] != "" {
		pulpInstanceName = os.Args[3]
	} else {
		pulpInstanceName = "ocp-example"
	}

	// pending check if it would be better to use
	//  https://pkg.go.dev/sigs.k8s.io/controller-runtime/pkg/client#Client

	// gather kubeconfig
	kubeconfig := filepath.Join("/etc", "kubeconfig", "config")

	// creates a helper that builds a config from kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		log.Fatalf("ERROR: Failed to configure the kubeconfig builder: %v", err)
	}

	// initialize the clientSet (Clientset contains the clients for groups)
	clientSet, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("ERROR: Failed to initialze the clientSet: %v", err)
	}

	pulp, err := getPulpInstance(clientSet, namespace, pulpInstanceName)
	if err != nil {
		log.Fatalf("ERROR: Failed to retrieve pulp instance: %v", err)
	}

	if !checkSA(clientSet, pulp, namespace, serviceAccountName) {
		os.Exit(1)
	}

	if !checkApiDeployment(clientSet, pulpInstanceName, namespace) {
		os.Exit(2)
	}

	os.Exit(0)
}

// checkSA returns true if the imagePullSecrets from Service Account are defined as expected
func checkSA(clientSet *kubernetes.Clientset, pulp map[string]interface{}, namespace, serviceAccountName string) bool {

	imagePullSecrets := []string{}

	if pulp["spec"].(map[string]interface{})["image_pull_secrets"] != nil {
		for _, secret := range pulp["spec"].(map[string]interface{})["image_pull_secrets"].([]interface{}) {
			imagePullSecrets = append(imagePullSecrets, secret.(string))
		}
	}

	// I'm not sure if this is a good idea because it needs to add permission to list and get secrets
	// probably not because we are already using a kubeconfig with a context defined to a kube-admin user.
	// We are collecting the secret used to pull from the internal ocp registry and adding it to []imagePullSecret.
	// This secret is automatically added by OCM (OpenShift Controller Manager) to the
	// .serviceAccount.imagePullSecret[]
	secrets, _ := clientSet.CoreV1().Secrets(namespace).List(context.TODO(), metav1.ListOptions{})
	for _, secret := range secrets.Items {
		if secret.ObjectMeta.Annotations["kubernetes.io/service-account.name"] == serviceAccountName {
			match, _ := regexp.MatchString(serviceAccountName+"-dockercfg-.*", secret.ObjectMeta.Name)
			if match {
				imagePullSecrets = append(imagePullSecrets, secret.ObjectMeta.Name)
				break
			}
		}
	}

	// get the list of imagePullSecrets defined in the service account
	// and store the secret names in []imagePullSecretsFromSA
	serviceAccounts, err := clientSet.CoreV1().ServiceAccounts(namespace).Get(context.TODO(), serviceAccountName, metav1.GetOptions{})
	if err != nil {
		log.Fatalf("ERROR: Failed to gather the list of service accounts from namespace %v: %v", namespace, err)
	}
	imagePullSecretsFromSA := []string{}
	for _, secret := range serviceAccounts.ImagePullSecrets {
		imagePullSecretsFromSA = append(imagePullSecretsFromSA, secret.Name)
	}

	log.Printf("imagePullSecrets from SA: %v\n", imagePullSecretsFromSA)
	log.Printf("imagePullSecrets expected: %v\n", imagePullSecrets)

	return reflect.DeepEqual(imagePullSecrets, imagePullSecretsFromSA)

}

func checkApiDeployment(clientSet *kubernetes.Clientset, pulpInstanceName, namespace string) bool {
	deployment, err := clientSet.AppsV1().Deployments(namespace).Get(context.TODO(), pulpInstanceName+"-api", metav1.GetOptions{})
	if err != nil {
		log.Fatalf("ERROR: Failed to get deployment %v from namespace %v: %v", pulpInstanceName+"api", namespace, err)
	}
	replicas := int32(1)
	expectedDeployment := &appsv1.Deployment{
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Args: []string{"pulp-content"},
						},
					},
				},
			},
		},
	}

	return equality.Semantic.DeepDerivative(expectedDeployment.Spec, deployment.Spec)
}
func checkApiService(clientSet *kubernetes.Clientset, pulpInstanceName, namespace string) bool {
	service, err := clientSet.CoreV1().Services(namespace).Get(context.TODO(), pulpInstanceName+"-api-svc", metav1.GetOptions{})
	if err != nil {
		log.Fatalf("ERROR: Failed to get service %v from namespace %v: %v", pulpInstanceName+"api-svc", namespace, err)
	}
	expectedService := &corev1.Service{}
	return equality.Semantic.DeepDerivative(expectedService.Spec, service.Spec)
}

func getPulpInstance(clientSet *kubernetes.Clientset, namespace, pulpInstanceName string) (map[string]interface{}, error) {

	// get pulp instance through rest api (returns an []byte)
	// we'll check the imagePullSecrets configured in this instace
	pulpInstanceRaw, err := clientSet.RESTClient().
		Get().
		AbsPath("/apis/pulp.pulpproject.org/v1beta1").
		Namespace(namespace).
		Resource("pulps").
		Name(pulpInstanceName).
		DoRaw(context.TODO())
	if err != nil {
		return nil, err
	}

	var pulpInstance map[string]interface{}
	if err = json.Unmarshal(pulpInstanceRaw, &pulpInstance); err != nil {
		return nil, err
	}

	return pulpInstance, nil

}
