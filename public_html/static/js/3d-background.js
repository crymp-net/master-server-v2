function init3DBackground(){
    let w = window.innerWidth;
    let h = window.innerHeight;

    const renderer = new PIXI.WebGLRenderer(w, h);
    const output = document.getElementById("wrap");

    const imgId = output.getAttribute("data-image")
    const fgPath = "/static/images/round_2/3D_FG" + imgId + ".jpg";
    const depthPath = "/static/images/round_2/3D_DM" + imgId + ".jpg";

    const loader = new PIXI.loaders.Loader();
    output.appendChild(renderer.view);

    renderer.view.style.width = "100vw";
    renderer.view.style.height = "100vh";

    let mouseX = w/2, mouseY = h/2;
    loader.add("diffuse",   fgPath)
    loader.add("depth",  depthPath)
    loader.once("complete", () => {
        const stage = new PIXI.Container();
        const box = new PIXI.Graphics();

        const diffuse = loader.resources.diffuse;
        const depth = loader.resources.depth;

        const filter = new PIXI.Filter(null, `
        precision mediump float;

        varying vec2 vTextureCoord;
        
        uniform sampler2D uSampler;
        uniform sampler2D diffuse;
        uniform sampler2D depth;
        
        uniform vec2 resolution;
        uniform vec2 cursor;
        uniform float ar;

        #define AR (16.0 / 9.0)

        void main(){
            vec2 pixel = 1.0 / resolution;
            vec2 disp = (cursor - 0.5) * 2.0 * pixel;
            vec2 uv = vec2(vTextureCoord.x, vTextureCoord.y);
            vec2 bias = vec2(1.0, 1.0);
            if(ar > AR){
                bias.y = AR / ar;
                uv.y += 1.0 - AR / ar;
            } else if(ar < AR) {
                bias.x = ar / AR;
                uv.x += 1.0 - ar / AR;
            }
            uv = uv * bias;
            disp = disp * bias;
            float vDepth = 1.0 - texture2D(depth, uv).r;
            vec2 distortedUv = uv - vDepth * disp * 7.0;
            vec3 vnColor = texture2D(diffuse, distortedUv).rgb;
            gl_FragColor = vec4(vnColor, 1.0);
        }`)


        filter.uniforms.diffuse = diffuse.texture;
        filter.uniforms.depth = depth.texture;

        function updateStage() {
            renderer.resize(diffuse.texture.width, diffuse.texture.height)
            filter.uniforms.resolution = [diffuse.texture.width, diffuse.texture.height];
            filter.uniforms.ar = window.innerWidth/(window.innerHeight - 100);
            
            box.beginFill(0x000000);
            box.drawRect(0, 0, diffuse.texture.width, diffuse.texture.height);
            box.endFill();
        }

        box.filters = [filter];

        stage.addChild(box);
        
        updateStage();

        function animate() {
            filter.uniforms.cursor = [
                mouseX / window.innerWidth,
                mouseY / window.innerHeight
            ];
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