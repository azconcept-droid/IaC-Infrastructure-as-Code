function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;

    %{~ for domain, bucket in sites ~}
    if (host === "${domain}" || host === "www.${domain}") {
        request.origin = {
            s3: {
                domainName: "${bucket}",
                region: "${aws_region}",
                authMethod: "sigv4"
            }
        };
    }
    %{~ endfor ~}

    return request;
}