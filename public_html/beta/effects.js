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

function readFloat(any) {
    const flt = parseFloat(any) || 0.0;
    if(isNaN(flt)) return 0.0;
    return flt;
}

class Effects {
    /**
     * 
     * @param {HTMLCanvasElement} output 
     */
    constructor(output){
        this.engine = new Engine(output);
        const engine = this.engine;
        const cursorPosition = [ 0, 0 ];
        const bbox = output.getBoundingClientRect()
        WIDTH = 1600;
        HEIGHT = 900;
        const resolution = [ WIDTH, HEIGHT ];

        console.log("Resolution", resolution)

        output.addEventListener("mousemove", (event) => {
            cursorPosition[0] = (event.offsetX - bbox.left) / bbox.width;
            cursorPosition[1] = (event.offsetY - bbox.top) / bbox.height;
        })

        const vertexShaderSource = document.getElementById("vs").innerHTML;
        
        const fragmentShaderSoruce = document.getElementById("fs").innerHTML;
        const entityFragmentShaderSource = document.getElementById("entityfs").innerHTML;
        const postFxFragmentShaderSource = document.getElementById("postfxfs").innerHTML;
        
        const vertexShader = new VertexShader(engine, vertexShaderSource);
        
        const fragmentShader = new FragmentShader(engine, fragmentShaderSoruce);
        const entityFragmentShader = new FragmentShader(engine, entityFragmentShaderSource);
        const postFxVertexShader = new FragmentShader(engine, postFxFragmentShaderSource);

        const program = new ShaderProgram(engine, [vertexShader, fragmentShader], {
            attributes: [ "vertexPosition", "vertexTexcoord", "vertexNormal" ],
            uniforms: [ "diffuse", "depth", "cursor", "resolution", "time", "distortionStrength" ]
        });

        const entitiesProgram = new ShaderProgram(engine, [vertexShader, entityFragmentShader], {
            attributes: [ "vertexPosition", "vertexTexcoord", "vertexNormal" ],
            uniforms: [ "diffuse", "depth", "image", "distort", "entity", "resolution", "cursor", "zinfo" ]
        });

        const postFxProgram = new ShaderProgram(engine, [vertexShader, postFxVertexShader], {
            attributes: [ "vertexPosition", "vertexTexcoord", "vertexNormal" ],
            uniforms: [ "diffuse", "depth", "overlay", "distort", "resolution", "distortionStrength" ]
        });

        engine.createAttributes(program);
        engine.useProgram(program);

        const Time = program.getUniform("time");

        const dmDistortionStrength = document.getElementById("fgds");
        const oDistortionStrength = document.getElementById("ods");
        
        const quad = new Quad(engine);

        const FgImage = new Texture2D(engine, {
            url: "../static/images/beta/FOREGROUND.jpg"
        });
        const FgDepth = new Texture2D(engine, {
            url: "../static/images/beta/DEPTHMAP.jpg"
        });

        const OverlayColor = new Texture2D(engine , {
            url: "../static/images/beta/OVERLAY.png"
        });
        const OverlayNormal = new Texture2D(engine, {
            url: "../static/images/beta/OVERLAY_DISTORT.png"
        })

        /**
         * @type {{[key: string]: Texture2D}}
         */
        const LU = {
            fg: FgImage,
            dm: FgDepth,
            od: OverlayNormal,
            oi: OverlayColor
        };

        document.querySelectorAll(".file-selector").forEach(sel => {
            const target = sel.id;

            sel.onchange = () => {
                const files = sel.files;
                if(files[0].type == "video/mp4") {
                    LU[target].loadVideo(URL.createObjectURL(files[0]));
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
            engine.clearColor(0.05, 0.05, 0.1);

            FgImage.bind(0);
            FgDepth.bind(1);
            program.getUniform("diffuse").set(FgImage);
            program.getUniform("depth").set(FgDepth);
            program.getUniform("resolution").set(resolution);
            program.getUniform("cursor").set(cursorPosition);
            program.getUniform("distortionStrength").set("1f", readFloat(dmDistortionStrength.value))
            
            Time.set("1f", timePassed);
            quad.draw(engine);

            engine.setRenderTarget(DeferDistortFB);

            engine.useProgram(entitiesProgram);
            engine.clearColor(0.5, 0.5, 0.5, 1.0);
            DeferDiffuse.bind(0);
            DeferDepth.bind(1);

            OverlayColor.bind(3);
            OverlayNormal.bind(4);

            entitiesProgram.getUniform("diffuse").set(DeferDiffuse);
            entitiesProgram.getUniform("depth").set(DeferDepth);

            entitiesProgram.getUniform("image").set(OverlayColor);
            entitiesProgram.getUniform("distort").set(OverlayNormal);

            entitiesProgram.getUniform("resolution").set(resolution);
            entitiesProgram.getUniform("cursor").set(cursorPosition);

            quad.draw(engine)

            engine.setRenderTarget(null);
            engine.useProgram(postFxProgram);
            engine.clearColor(1, 0, 0);
            DeferDiffuse.bind(0);
            DeferDepth.bind(1);
            DeferColor.bind(2);
            DeferDistort.bind(3);

            postFxProgram.getUniform("diffuse").set(DeferDiffuse);
            postFxProgram.getUniform("depth").set(DeferDepth);
            postFxProgram.getUniform("overlay").set(DeferColor);
            postFxProgram.getUniform("distort").set(DeferDistort);
            postFxProgram.getUniform("distortionStrength").set("1f", readFloat(oDistortionStrength.value))

            postFxProgram.getUniform("resolution").set(resolution);

            engine.clearColor(0, 1, 0);
            quad.draw(engine);
        });

        window.engine = engine;

        this.engine.beginRendering();
    }
}

window.onload = () => {
    new Effects(document.getElementById("target"));
}