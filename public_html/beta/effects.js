import {
    Engine, 
    ShaderProgram,
    VertexShader,
    FragmentShader,
    Texture2D,
    FrameBuffer,
    Quad
} from "./engine.js";

let WIDTH = 1600;
let HEIGHT = 900;

class Effects {
    /**
     * 
     * @param {HTMLCanvasElement} output 
     */
    constructor(output){
        this.engine = new Engine(output);
        this.video = document.createElement("video");
        this.video.autoplay = true;
        this.video.muted = true;
        this.video.loop = true;
        const engine = this.engine;
        const cursorPosition = [ 0, 0 ];
        const bbox = output.getBoundingClientRect()
        WIDTH = bbox.right - bbox.left;
        HEIGHT = bbox.bottom - bbox.top;
        const resolution = [ WIDTH, HEIGHT ];

        output.addEventListener("mousemove", (event) => {
            const rectangle = output.getBoundingClientRect();
            cursorPosition[0] = event.offsetX / rectangle.width;
            cursorPosition[1] = event.offsetY / rectangle.height;
        })

        const vertexShaderSource = document.getElementById("vs").innerHTML;
        const fragmentShaderSoruce = document.getElementById("fs").innerHTML;

        const entityVertexShaderSource = document.getElementById("entityvs").innerHTML;
        const entityFragmentShaderSource = document.getElementById("entityfs").innerHTML;

        const postFxFragmentShaderSource = document.getElementById("postfxfs").innerHTML;
        
        const vertexShader = new VertexShader(engine, vertexShaderSource);
        const fragmentShader = new FragmentShader(engine, fragmentShaderSoruce);
        const entityVertexShader = new VertexShader(engine, entityVertexShaderSource);
        const entityFragmentShader = new FragmentShader(engine, entityFragmentShaderSource);
        const postFxVertexShader = new FragmentShader(engine, postFxFragmentShaderSource);

        const program = new ShaderProgram(engine, [vertexShader, fragmentShader], {
            attributes: [ "vertexPosition", "vertexTexcoord", "vertexNormal" ],
            uniforms: [ "diffuse", "depth", "cursor", "resolution", "time" ]
        });

        const entitiesProgram = new ShaderProgram(engine, [entityVertexShader, entityFragmentShader], {
            attributes: [ "vertexPosition", "vertexTexcoord", "vertexNormal" ],
            uniforms: [ "diffuse", "depth", "image", "distort", "entity", "resolution", "cursor", "zinfo" ]
        });

        const postFxProgram = new ShaderProgram(engine, [vertexShader, postFxVertexShader], {
            attributes: [ "vertexPosition", "vertexTexcoord", "vertexNormal" ],
            uniforms: [ "diffuse", "depth", "overlay", "distort", "resolution" ]
        });

        engine.createAttributes(program);
        engine.useProgram(program);

        const Time = program.getUniform("time");

        const entityPosition = entitiesProgram.getUniform("entity");
        const zinfo = entitiesProgram.getUniform("zinfo");
        
        const quad = new Quad(engine);

        const FgImage = new Texture2D(engine, {
            url: "../static/images/beta/FOREGROUND.jpg"
        });
        const FgDepth = new Texture2D(engine, {
            url: "../static/images/beta/DEPTHMAP.jpg"
        });

        const RaindropImage = new Texture2D(engine , {
            url: "../static/images/beta/OVERLAY.png"
        });
        const RaindropDistort = new Texture2D(engine, {
            url: "../static/images/beta/OVERLAY_DISTORT.png"
        })

        const LU = {
            fg: FgImage,
            dm: FgDepth,
            od: RaindropDistort,
            oi: RaindropImage
        };
 
        this.video.onload = () => {
            LU[target].loadVideo(this.video);
        }

        document.querySelectorAll(".file-selector").forEach(sel => {
            const target = sel.id;

            sel.onchange = () => {
                const files = sel.files;
                if(files[0].type == "video/mp4") {
                    this.video.src = URL.createObjectURL(files[0]);
                    this.video.play()
                    LU[target].loadVideo(this.video);
                } else {
                    LU[target].loadImage({ url: URL.createObjectURL(files[0]) })
                }
            }
        })

        const DeferDiffuse = new Texture2D(engine, { width: WIDTH, height: HEIGHT, slot: 0 });
        const DeferDepth = new Texture2D(engine, { width: WIDTH, height: HEIGHT, slot: 1 });

        const DeferColor = new Texture2D(engine, { width: WIDTH, height: HEIGHT, slot: 0 });
        const DeferDistort = new Texture2D(engine, { width: WIDTH, height: HEIGHT, slot: 1 });
        
        const DeferFB = new FrameBuffer(engine, [ DeferDiffuse, DeferDepth ], true);
        const DeferDistortFB = new FrameBuffer(engine, [ DeferColor, DeferDistort ], true);

        let timePassed = 0;

        const entities = [];

        /*
        for(let i = 0; i < 500; i++) {
            entities.push({x: Math.random(), y: Math.random(), dx: Math.random(), z: Math.random(), dy: -1, life: 0})
        }
        */
       entities.push({x: 0, y: 0, dx: 0, dy: 0, z: 1, life: 0})

        this.engine.onFrame( (engine, deltaTime) => {
            timePassed += deltaTime;

            
            for (const key in LU) {
                if (Object.hasOwnProperty.call(LU, key)) {
                    const element = LU[key];
                    element.update();
                }
            }

            engine.setRenderTarget(DeferFB);
            engine.useProgram(program);
            engine.clearColor(0, 0, 0);
            FgImage.bind(0);
            FgDepth.bind(1);
            program.getUniform("diffuse").set(FgImage);
            program.getUniform("depth").set(FgDepth);
            program.getUniform("resolution").set(resolution);
            program.getUniform("cursor").set(cursorPosition);
            
            Time.set("1f", timePassed);
            quad.draw(engine);

            engine.setRenderTarget(DeferDistortFB);

            engine.useProgram(entitiesProgram);
            engine.clearColor(0.5, 0.5, 0.5, 1.0);
            DeferDiffuse.bind(0);
            DeferDepth.bind(1);

            RaindropImage.bind(3);
            RaindropDistort.bind(4);

            entitiesProgram.getUniform("diffuse").set(DeferDiffuse);
            entitiesProgram.getUniform("depth").set(DeferDepth);

            entitiesProgram.getUniform("image").set(RaindropImage);
            entitiesProgram.getUniform("distort").set(RaindropDistort);

            entitiesProgram.getUniform("resolution").set(resolution);
            entitiesProgram.getUniform("cursor").set(cursorPosition);

            entityPosition.set([0.5, 0.5, 1, 1])
            quad.draw(engine)

            engine.setRenderTarget(null);
            engine.useProgram(postFxProgram);
            engine.clearColor(0, 0, 0);
            DeferDiffuse.bind(0);
            DeferDepth.bind(1);
            DeferColor.bind(2);
            DeferDistort.bind(3);

            postFxProgram.getUniform("diffuse").set(DeferDiffuse);
            postFxProgram.getUniform("depth").set(DeferDepth);
            postFxProgram.getUniform("overlay").set(DeferColor);
            postFxProgram.getUniform("distort").set(DeferDistort);

            postFxProgram.getUniform("resolution").set(resolution);

            engine.clearColor(0, 0, 0);
            quad.draw(engine);
        });

        window.engine = engine;

        this.engine.beginRendering();
    }
}

window.onload = () => {
    new Effects(document.getElementById("target"));
}