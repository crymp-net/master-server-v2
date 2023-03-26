function init3DBackground(){
    let w = window.innerWidth;
    let h = window.innerHeight;

    const renderer = new PIXI.WebGLRenderer(w, h);
    const output = document.getElementById("wrap");

    const imgId = output.getAttribute("data-image")
    const fgPath = "/static/images/3D_" + imgId + "FG.jpg";
    const depthPath = "/static/images/3D_" + imgId + "DM.jpg";

    const stage = new PIXI.Container();
    const foreground = new PIXI.Container();
    const loader = new PIXI.loaders.Loader();
    stage.addChild(foreground); 
    output.appendChild(renderer.view);

    let mouseX = w/2, mouseY = h/2;
    loader.add("fg",     fgPath)
    loader.add("depth",  depthPath)
    loader.once("complete", () => {
        const fg = new PIXI.Sprite(loader.resources.fg.texture);
        const depth = new PIXI.Sprite(loader.resources.depth.texture)
        const filter = new PIXI.filters.DisplacementFilter(depth, 0);

        function updateStage() {
            renderer.resize(window.innerWidth, window.innerHeight)
            stage.scale.x = Math.max(window.innerWidth / fg.width, window.innerHeight / fg.height)
            stage.scale.y = stage.scale.x;
        }


        updateStage();

        depth.renderable = false;
        fg.addChild(depth);
        foreground.addChild(fg);    
        
        fg.filters = [filter];

        function animate() {
            filter.scale.x = 20 * (window.innerWidth/2 - mouseX) / window.innerWidth;
            filter.scale.y = 20 * (window.innerHeight/2 - mouseY) / window.innerHeight;
            renderer.render(stage);       
        }

        window.addEventListener("resize", () => {
            updateStage();
            requestAnimationFrame(animate)
        })
        window.addEventListener("mousemove", (e) => {
            mouseX = e.clientX;
            mouseY = e.clientY;
            requestAnimationFrame(animate);
        })
        window.addEventListener("touchmove", (e) => {
            if(e.touches.length < 1) return;
            const t = e.touches[0]
            mouseX = t.clientX;
            mouseY = t.clientY;
            requestAnimationFrame(animate);
        })
        requestAnimationFrame(animate);
    });
    loader.load();
}

window.addEventListener("load", () => {
    init3DBackground()
})