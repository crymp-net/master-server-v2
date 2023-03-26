function changeMapPicture(el){
    var fd = new FormData();
    var file = el;
    var mapName = el.getAttribute("data-map");
    if(file.files.length == 1){
        fd.append("file", file.files[0]);
        fd.append("mapName", mapName);
        fd.append("csrf", document.getElementById("map_csrf").value)
        $.ajax({
            url: "/api/map_picture",
            type: "POST",
            data: fd,
            processData: false,
            contentType: false
        }).done((function(resp){
            if(!resp.error){
                var imgs = document.getElementsByName(mapName);
                for(var i=0; i<imgs.length; i++)
                    imgs[i].src = resp.path;
            } else alert(resp.error);
        }));
    }
}