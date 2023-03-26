function changeProfilePicture(){
    var fd = new FormData();
    var file = document.getElementById("file");
    if(file.files.length == 1){
        fd.append("file", file.files[0]);
        fd.append("csrf", document.getElementById("profile_csrf").value)
        $.ajax({
            url: "/api/profile_picture",
            type: "POST",
            data: fd,
            processData: false,
            contentType: false
        }).done((function(resp){
            if(!resp.error){
                document.getElementById('profile-picture').style.backgroundImage = "url(\""+resp.path+"\")";
            } else alert(resp.error);
        }));
    }
}