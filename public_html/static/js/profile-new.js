function changeProfilePicture() {
    var fileInput = document.getElementById("file");
    if (fileInput.files.length === 1) {
        var file = fileInput.files[0];
        var csrfToken = document.getElementById("e").value;

        $.ajax({
            url: csrfToken,
            type: "POST",
            data: file,
            processData: false,
            contentType: file.type || "application/octet-stream",
        }).done(function(resp) {
            console.log(resp);
            if (!resp.error) {
                document.getElementById('profile-picture').style.backgroundImage = "url(\"" + resp.path + "\")";
            } else {
                alert(resp.error);
            }
        });
    }
}