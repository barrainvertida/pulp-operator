package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"time"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	v1 "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
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
	//kubeconfig := filepath.Join("/tmp", "kubeconfig")

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

	// get pulp instance
	pulp, err := getPulpInstance(clientSet, namespace, pulpInstanceName)
	if err != nil {
		log.Fatalf("ERROR: Failed to retrieve pulp instance: %v", err)
	}

	// verify imagepullsecrets from pulp-operator SA
	if !checkSA(clientSet, pulp, namespace, serviceAccountName) {
		log.Fatal("ERROR: Service Account imagePullSecrets not matching the expected secrets!")
		os.Exit(1)
	} else {
		log.Printf("INFO: imagePullSecrets from SA OK ...")
	}

	// add new Secrets to image_pull_secret
	log.Println("INFO: updating pulp with new image_pull_secrets ...")
	newSecretsRaw := `[{"op": "add", "path": "/spec/image_pull_secrets", "value": ["test-C","test-E"] }]`
	_, err = clientSet.RESTClient().Patch(types.JSONPatchType).
		AbsPath("/apis/pulp.pulpproject.org/v1beta1/namespaces/" + namespace + "/pulps/" + pulpInstanceName).
		Body([]byte(newSecretsRaw)).
		DoRaw(context.TODO())
	if err != nil {
		log.Println("ERROR: ", err)
	}

	// get the updated pulp instance spec
	pulp, err = getPulpInstance(clientSet, namespace, pulpInstanceName)
	if err != nil {
		log.Fatalf("ERROR: Failed to retrieve pulp instance: %v", err)
	}

	// since pulp is a CRD we don't have a wait() method on client-go, so we created the waitPulpUpdate() function
	time.Sleep(15 * time.Second)
	waitPulpUpdate(clientSet, namespace, pulpInstanceName)

	//check imagepullsecrets again
	if !checkSA(clientSet, pulp, namespace, serviceAccountName) {
		log.Fatal("ERROR: Service Account imagePullSecrets not matching the expected secrets after adding new secrets to image_pull_secrets!")
		os.Exit(2)
	} else {
		log.Printf("INFO: New imagePullSecrets added ...")
	}

	// remove image_pull_secret definition
	log.Println("INFO: updating pulp with new image_pull_secrets ...")
	newSecretsRaw = `[{"op": "remove", "path": "/spec/image_pull_secrets"}]`
	_, err = clientSet.RESTClient().Patch(types.JSONPatchType).
		AbsPath("/apis/pulp.pulpproject.org/v1beta1/namespaces/" + namespace + "/pulps/" + pulpInstanceName).
		Body([]byte(newSecretsRaw)).
		DoRaw(context.TODO())
	if err != nil {
		log.Println("ERROR: ", err)
	}

	// get the updated pulp instance spec
	pulp, err = getPulpInstance(clientSet, namespace, pulpInstanceName)
	if err != nil {
		log.Fatalf("ERROR: Failed to retrieve pulp instance: %v", err)
	}

	// since pulp is a CRD we don't have a wait() method on client-go, so we created the waitPulpUpdate() function
	time.Sleep(15 * time.Second)
	waitPulpUpdate(clientSet, namespace, pulpInstanceName)

	//check imagepullsecrets again
	if !checkSA(clientSet, pulp, namespace, serviceAccountName) {
		log.Fatal("ERROR: Service Account imagePullSecrets not matching the expected secrets after removing image_pull_secret definition from pulp instance!")
		os.Exit(2)
	} else {
		log.Printf("INFO: imagePullSecrets from SA updated ...")
	}

	// check pulp-api deployment
	if !checkApiDeployment(clientSet, pulpInstanceName, namespace) {
		log.Fatal("ERROR: " + pulpInstanceName + "-api deployment not matching the expected deployment!")
		os.Exit(3)
	} else {
		log.Printf("INFO: API Deployment spec OK ...")
	}

	// check pulp-api-svc service
	if !checkApiService(clientSet, pulpInstanceName, namespace) {
		log.Fatal("ERROR: " + pulpInstanceName + "-api-svc service not matching the expected spec!")
		os.Exit(4)
	} else {
		log.Printf("INFO: API Service spec OK ...")
	}

	log.Printf("SA, Service and Deployment checks OK!")
	os.Exit(0)
}

// checkSA returns true if the imagePullSecrets from Service Account are
// defined with the expected image_pull_secrets and the secret to pull from internal registry
func checkSA(clientSet *kubernetes.Clientset, pulp map[string]interface{}, namespace, serviceAccountName string) bool {

	imagePullSecrets := []string{}

	if pulp["spec"].(map[string]interface{})["image_pull_secrets"] != nil {
		for _, secret := range pulp["spec"].(map[string]interface{})["image_pull_secrets"].([]interface{}) {
			imagePullSecrets = append(imagePullSecrets, secret.(string))
		}
	}

	// I'm not sure if this is a good idea because it needs to add permission to list and get secrets
	// probably not an issue because we are already using a kubeconfig with a context defined to a kube-admin user.
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

	return reflect.DeepEqual(imagePullSecrets, imagePullSecretsFromSA)
}

// checkApiDeployment returns true if pulp-api deployment matches the expected spec
// maybe a better check would be to do granular checks (for example, a check for .spec.template.spec.containers, another one for
// .spec.template.spec.volumes, etc) this way would be easier to find why/where it failed.
// for now, we are just checking some "core" specs
func checkApiDeployment(clientSet *kubernetes.Clientset, pulpInstanceName, namespace string) bool {
	deployment, err := clientSet.AppsV1().Deployments(namespace).Get(context.TODO(), pulpInstanceName+"-api", metav1.GetOptions{})
	if err != nil {
		log.Fatalf("ERROR: Failed to get deployment %v from namespace %v: %v", pulpInstanceName+"api", namespace, err)
	}
	replicas := int32(1)
	secretDefaultMode := int32(420)
	expectedDeployment := &appsv1.Deployment{
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Args: []string{"pulp-api"},
							Env: []corev1.EnvVar{
								{
									Name:  "POSTGRES_SERVICE_HOST",
									Value: pulpInstanceName + "-postgres-13",
								}, {
									Name:  "POSTGRES_SERVICE_PORT",
									Value: "5432",
								}, {
									Name:  "REDIS_SERVICE_HOST",
									Value: pulpInstanceName + "-redis-svc",
								}, {
									Name:  "REDIS_SERVICE_PORT",
									Value: "6379",
								}, {
									Name:  "PULP_GUNICORN_TIMEOUT",
									Value: "90",
								}, {
									Name:  "PULP_API_WORKERS",
									Value: "2",
								},
							},
							Image: "quay.io/pulp/pulp:latest",
							Name:  "api",
							Ports: []corev1.ContainerPort{
								{
									ContainerPort: 24817,
									Protocol:      corev1.ProtocolTCP,
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{
									MountPath: "/etc/pulp/settings.py",
									Name:      pulpInstanceName + "-server",
									ReadOnly:  true,
									SubPath:   "settings.py",
								}, {
									MountPath: "/etc/pulp/pulp-admin-password",
									Name:      pulpInstanceName + "-admin-password",
									ReadOnly:  true,
									SubPath:   "admin-password",
								}, {
									MountPath: "/etc/pulp/keys/database_fields.symmetric.key",
									Name:      pulpInstanceName + "-db-fields-encryption",
									ReadOnly:  true,
									SubPath:   "database_fields.symmetric.key",
								}, {
									MountPath: "/var/lib/pulp",
									Name:      "file-storage",
								}, {
									MountPath: "/etc/pulp/keys/container_auth_private_key.pem",
									Name:      pulpInstanceName + "-container-auth-certs",
									ReadOnly:  true,
									SubPath:   "container_auth_private_key.pem",
								}, {
									MountPath: "/etc/pulp/keys/container_auth_public_key.pem",
									Name:      pulpInstanceName + "-container-auth-certs",
									ReadOnly:  true,
									SubPath:   "container_auth_public_key.pem",
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: pulpInstanceName + "-server",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{
									SecretName:  pulpInstanceName + "-server",
									DefaultMode: &secretDefaultMode,
									Items: []corev1.KeyToPath{{
										Key:  "settings.py",
										Path: "settings.py",
									}},
								},
							},
						}, {
							Name: pulpInstanceName + "-admin-password",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{
									SecretName:  "example-pulp-admin-password", // this secret name is strange
									DefaultMode: &secretDefaultMode,
									Items: []corev1.KeyToPath{{
										Key:  "password",
										Path: "admin-password",
									}},
								},
							},
						}, {
							Name: pulpInstanceName + "-db-fields-encryption",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{
									SecretName:  pulpInstanceName + "-db-fields-encryption",
									DefaultMode: &secretDefaultMode,
									Items: []corev1.KeyToPath{{
										Key:  "database_fields.symmetric.key",
										Path: "database_fields.symmetric.key",
									}},
								},
							},
						}, {
							Name: "file-storage",
							VolumeSource: corev1.VolumeSource{
								PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
									ClaimName: pulpInstanceName + "-file-storage",
								},
							},
						}, {
							Name: pulpInstanceName + "-container-auth-certs",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{
									SecretName:  pulpInstanceName + "-container-auth",
									DefaultMode: &secretDefaultMode,
									Items: []corev1.KeyToPath{{
										Key:  "container_auth_public_key.pem",
										Path: "container_auth_public_key.pem",
									}, {
										Key:  "container_auth_private_key.pem",
										Path: "container_auth_private_key.pem",
									},
									},
								},
							},
						},
					},
				},
			},
		},
	}

	return equality.Semantic.DeepDerivative(expectedDeployment.Spec, deployment.Spec)
}

// checkApiService returns true if pulp-api-svc service is with the expected spec
// we are not comparing every field from service because some (like ClusterIP) vary
// on provisioning
func checkApiService(clientSet *kubernetes.Clientset, pulpInstanceName, namespace string) bool {
	deploymentType := getDeploymentType(clientSet, namespace, pulpInstanceName)
	service, err := clientSet.CoreV1().Services(namespace).Get(context.TODO(), pulpInstanceName+"-api-svc", metav1.GetOptions{})
	if err != nil {
		log.Fatalf("ERROR: Failed to get service %v from namespace %v: %v", deploymentType+"api-svc", namespace, err)
	}
	expectedService := &corev1.Service{
		Spec: corev1.ServiceSpec{
			Type: corev1.ServiceTypeClusterIP,
			Ports: []corev1.ServicePort{
				{
					Name:       "api-24817",
					Port:       24817,
					Protocol:   corev1.ProtocolTCP,
					TargetPort: intstr.IntOrString{IntVal: 24817},
				},
			},
			Selector: map[string]string{
				"app.kubernetes.io/component":  "api",
				"app.kubernetes.io/instance":   deploymentType + "-api-" + pulpInstanceName,
				"app.kubernetes.io/managed-by": deploymentType + "-operator",
				"app.kubernetes.io/name":       deploymentType + "-api",
				"app.kubernetes.io/part-of":    deploymentType,
			},
		},
	}
	return equality.Semantic.DeepDerivative(expectedService.Spec, service.Spec)
}

// getPulpInstance returns pulp CR instance object definition
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

// waitPulpUpdate is like the 'kubectl wait' command, it will put the program execution
// "on hold" until a condition is met
func waitPulpUpdate(clientSet *kubernetes.Clientset, namespace, pulpInstanceName string) {

	deploymentType := getDeploymentType(clientSet, namespace, pulpInstanceName)
	for timeOut := 0; timeOut <= 10; timeOut++ {
		pulpInstance, _ := getPulpInstance(clientSet, namespace, pulpInstanceName)
		conditions := []metav1.Condition{}
		for _, condition := range pulpInstance["status"].(map[string]interface{})["conditions"].([]interface{}) {
			// doing a "manual unmarshall" (could not make it work with json.Unmarshal)
			//  tmpCondition := metav1.Condition{}
			//  json.Unmarshal(condition.(map[string]interface{}), &tmpCondition)
			auxCondition := metav1.Condition{
				Type:   condition.(map[string]interface{})["type"].(string),
				Status: metav1.ConditionStatus(condition.(map[string]interface{})["status"].(string)),
			}
			conditions = append(conditions, auxCondition)
		}

		if v1.IsStatusConditionTrue(conditions, cases.Title(language.English, cases.Compact).String(deploymentType)+"-Operator-Finished-Execution") {
			break
		}

		log.Println("pulp-operator running updates ...")
		time.Sleep(30 * time.Second)
	}
}

// getDeploymentType returns the type of provisioning (pulp|galaxy)
func getDeploymentType(clientSet *kubernetes.Clientset, namespace, pulpInstanceName string) string {
	deploymentType := ""
	pulpInstance, _ := getPulpInstance(clientSet, namespace, pulpInstanceName)
	if pulpInstance["spec"].(map[string]interface{})["deployment_type"] != nil {
		deploymentType = pulpInstance["spec"].(map[string]interface{})["deployment_type"].(string)
	} else {
		deploymentType = "pulp"
	}
	return deploymentType
}
