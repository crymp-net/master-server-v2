export class Uniform {
    /**
     * Initialize uniform
     * @param {Engine} engine 
     * @param {ShaderProgram} program 
     * @param {*} name 
     */
    constructor(engine, program, name){
        const ctx = engine.getContext();
        this.gl = ctx;
        this.location = ctx.getUniformLocation(program.program, name);
    }

    /**
     * Set uniform value
     * @param {string|number|Array<number>|Array<Array<number>>} type type or value
     * @param {(number|Array<number>|Array<Array<number>>)?} value value
     */
    set(type, value){
        if(typeof(value) == "undefined"){
            let postfix = "fv";
            let resolution = "";
            let prefix = "";
            value = type;
            if(value instanceof Array){
                if(value[0] instanceof Array){
                    prefix = "Matrix";
                    if(value[0].length == value.length){
                        resolution = value[0].length.toString();
                    } else {
                        resolution = value.length + "x" + value[0].length;
                    }
                } else {
                    resolution = value.length.toString();
                }
                this.gl["uniform" + prefix + resolution + postfix](this.location, value);
            } else if(value instanceof Float32Array){
                this.gl.uniformMatrix4fv(this.location, false, value);
            } else if(value instanceof Texture2D){
                this.gl.uniform1i(this.location, value instanceof Number ? value : value.slot);
            } else if(typeof(value) == "number"){
                this.gl.uniform1i(this.location, value);
            }
        } else {
            this.gl["uniform" + type](this.location, value);
        }
    }
}

export class Attribute {
    /**
     * Initialize attribute
     * @param {Engine} engine 
     * @param {ShaderProgram} program 
     * @param {*} name 
     */
    constructor(engine, program, name){
        const ctx = engine.getContext();
        this.gl = ctx;
        this.location = ctx.getAttribLocation(program.program, name);
    }
}

export class Shader {
    /**
     * 
     * @param {Engine} engine 
     * @param {number} type 
     * @param {string} code 
     */
    constructor(engine, type, code){
        const ctx = engine.getContext();
        if(!code.startsWith("#version")) code = "#version 300 es\n" + code;
        this.shader = ctx.createShader(type);
        ctx.shaderSource(this.shader, code);
        ctx.compileShader(this.shader);
        if(!ctx.getShaderParameter(this.shader, ctx.COMPILE_STATUS)){
            const err = {
                error: "invalid shader",
                details: ctx.getShaderInfoLog(this.shader).split("\n")
            };
            ctx.deleteShader(this.shader);
            this.shader = null;
            throw err;
        }
    }
}

export class FragmentShader extends Shader {
    /**
     * Initialize fragment shader
     * @param {Engine} engine 
     * @param {string} code 
     */
    constructor(engine, code){
        super(engine, engine.getContext().FRAGMENT_SHADER, code);
    }
}

export class VertexShader extends Shader {
    /**
     *  Initialize vertex shader
     * @param {Engine} engine 
     * @param {string} code 
     */
    constructor(engine, code){
        super(engine, engine.getContext().VERTEX_SHADER, code);
    }
}

export class ShaderProgram {
    /**
     * Initialize shader program
     * @param {Engine} engine engine reference
     * @param {Array<Shader>} shaders shader array
     * @param {{attributes: Array<string>, uniforms: Array<string>}?} spec attributes and uniforms specification 
     */
    constructor(engine, shaders, spec){
        const ctx = engine.getContext();
        this.gl = ctx;
        this.positions = {};
        this.program = ctx.createProgram();
        for(let i = 0; i< shaders.length; i++){
            ctx.attachShader(this.program, shaders[i].shader);
        }
        ctx.linkProgram(this.program);
        if(!ctx.getProgramParameter(this.program, ctx.LINK_STATUS)){
            const err = {
                error: "failed to create program",
                details: ctx.getProgramInfoLog(this.program)
            };
            ctx.deleteProgram(this.program);
            this.program = null;
            throw err;
        }
        if(typeof(spec) != "undefined"){
            if(spec.uniforms){
                this.positions.uniforms = {};
                for(let k = 0; k<spec.uniforms.length; k++){
                    let name = spec.uniforms[k];
                    this.positions.uniforms[name] = new Uniform(engine, this, name);
                }
            }
            if(spec.attributes){
                this.positions.attributes = {};
                for(let k = 0; k<spec.attributes.length; k++){
                    let name = spec.attributes[k];
                    this.positions.attributes[name] = new Attribute(engine, this, name);
                }
            }
        }
    }

    /**
     * Use shader program
     */
    use(){
        this.gl.useProgram(this.program);
    }

    /**
     * Get attributes
     * @returns {Map<string, Attribute>} attributes
     */
    getAttributes(){
        return this.positions.attributes || {};
    }

    /**
     * Get uniforms
     * @returns {Map<String, Uniform>} attributes
     */
    getUniforms(){
        return this.positions.uniforms || {};
    }

    /**
     * Get attribute by name
     * @param {string} name
     * @returns {Attribute} attrib 
     */
    getAttribute(name){
        return this.getAttributes()[name];
    }

    /**
     * Get uniform by name
     * @param {string} name
     * @returns {Uniform} uniform 
     */
    getUniform(name){
        return this.getUniforms()[name];
    }
}

export class GlBuffer {
    /**
     * 
     * @param {Engine} engine 
     * @param {Array<number>} data 
     * @param {number} bufferType
     * @param {number} drawType 
     */
    constructor(engine, data, bufferType, drawType){
        const ctx = engine.getContext();
        this.gl = ctx;
        drawType = drawType || ctx.STATIC_DRAW;
        bufferType = bufferType || ctx.ARRAY_BUFFER;
        this.buffer = ctx.createBuffer();
        this.bufferType = bufferType;
        this.drawType = drawType;
        this.bind(this.bufferType);
        ctx.bufferData(
            this.bufferType, 
            this.bufferType == this.gl.ELEMENT_ARRAY_BUFFER?new Uint16Array(data):new Float32Array(data),
            drawType
        );
    }

    /**
     * Bind buffer
     * @param {number?} position 
     */
    bind(position){
        this.gl.bindBuffer(position || this.bufferType, this.buffer);
    }
}

export class VertexBuffer extends GlBuffer {
    /**
     * Initialize vertex buffer
     * @param {Engine} engine 
     * @param {Array<number>} data 
     * @param {AttributeDefinition} attributes
     * @param {number} drawType 
     */
    constructor(engine, data, attributes, drawType){
        super(engine, data, engine.getContext().ARRAY_BUFFER, drawType);
        const ctx = engine.getContext();
        this.vertexArray = ctx.createVertexArray();
        ctx.bindVertexArray(this.vertexArray);
        attributes.bind();
    }

    bind(slot){
        super.bind(slot);
        this.gl.bindVertexArray(this.vertexArray);
    }
}

export class IndexBuffer extends GlBuffer {
    /**
     * Initialize vertex buffer
     * @param {Engine} engine 
     * @param {Array<number>} data 
     * @param {number} drawType 
     */
    constructor(engine, data, drawType){
        super(engine, data, engine.getContext().ELEMENT_ARRAY_BUFFER, drawType);
    }
}

class ImageWrapper {
    constructor(){
        this.image = null;
        this.isJson = false;
        this.format = "rgb";
    }

    /**
     * Set source path
     * @param {String} path 
     */
    setSource(path){
        if(path.endsWith(".float.json")){
            this.isJson = true;
            this.f32 = new Float32Array([0.0]);
            this.width = 1;
            this.height = 1;
            const xhr = new XMLHttpRequest();
            xhr.responseType = "json";
            xhr.onload = () => {
                const data = xhr.response;
                this.width = data.width;
                this.height = data.height;
                this.f32 = new Float32Array(data.data);
                this.format = "float";
                typeof(this.onload) == "function" && this.onload();
            }
            xhr.open("GET", path);
            xhr.send();
        } else {
            this.image = new Image();
            this.image.crossOrigin = "anonymous";
            this.isJson = false;
            this.format = "rgb";
            this.image.onload = () => {
                this.width = this.image.width;
                this.height = this.image.height;
                typeof(this.onload) == "function" && this.onload();
            }
            this.image.src = path;
        }
    }

    getData(){
        if(this.isJson){
            return this.f32;
        }
        return this.image;
    }

}

export class Texture2D {
    /**
     * Initialize texture
     * @param {Engine} engine 
     * @param {{
     *  width: number,
     *  height: number,
     *  format: number?,
     *  internalFormat: number?, 
     *  type: number?,
     *  hdr: boolean?,
     *  normal: boolean?,
     *  depth: boolean?,
     *  url: string?
     * }} params 
     */
    constructor(engine, params){
        let {width, height, format, internalFormat, type} = params;
        const ctx = engine.getContext();
        this.gl = ctx;

        type = type || this.gl.UNSIGNED_BYTE;
        format = format || this.gl.RGBA;
        internalFormat = internalFormat || this.gl.RGBA;

        if(params.depth){
            type = this.gl.UNSIGNED_INT;
            format = this.gl.DEPTH_COMPONENT;
            internalFormat = this.gl.DEPTH_COMPONENT24;
            this.depth = true;
        } else {
            this.depth = false;
        }

        this.texture = this.gl.createTexture();
        this.width = width;
        this.height = height;
        this.format = format;
        this.internalFormat = internalFormat;
        this.type = type;
        this.level = 0;
        this.border = 0;
        /**
         * @type {HTMLVideoElement?}
         */
        this.video = null;
        this.isVideo = false;
        this.normal = params.normal || false;
        this.slot = params.slot || 0;

        this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
        this.loadImage(params, true)
    }

    /**
     * Initialize texture
     * @param {Engine} engine 
     * @param {{
    *  width: number,
    *  height: number,
    *  format: number?,
    *  internalFormat: number?, 
    *  type: number?,
    *  hdr: boolean?,
    *  normal: boolean?,
    *  depth: boolean?,
    *  url: string?
    * }} params 
    */
    loadImage(params, bind) {
        this.isVideo = false;
        if(this.video && !this.video.paused) {
            this.video.pause();
        }

        function isPowerOf2(value){
            return (value & (value - 1)) == 0;
        }

        if(params.url){
            const image = new ImageWrapper();
            const self = this;

            image.onload = (() => {
                self.gl.bindTexture(self.gl.TEXTURE_2D, self.texture);
                if(image.format == "rgb") {
                    self.gl.texImage2D(self.gl.TEXTURE_2D, self.level, self.internalFormat, self.format, self.type, image.getData());
                } else if(image.format == "float") {
                    self.internalFormat = self.gl.R32F;
                    self.format = self.gl.RED;
                    self.type = self.gl.FLOAT;
                    self.gl6.texImage2D(self.gl.TEXTURE_2D, self.level, self.internalFormat, image.width, image.height, self.border, self.format, self.type, image.getData());
                }
                self.width = image.width;
                self.height = image.height;

                if (isPowerOf2(image.width) && isPowerOf2(image.height)) {
                    self.gl.generateMipmap(self.gl.TEXTURE_2D);
                } else {
                    self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_WRAP_S, self.gl.CLAMP_TO_EDGE);
                    self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_WRAP_T, self.gl.CLAMP_TO_EDGE);
                    self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MIN_FILTER, self.gl.LINEAR);
                }
            });
            image.setSource(params.url);
        } else {
            const data = params.data || null;
            this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
            this.gl.texImage2D(this.gl.TEXTURE_2D, this.level, this.internalFormat, this.width, this.height, this.border, this.format, this.type, data);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
        }
    }

    /**
     * Load video
     * @param {string} src 
     */
    loadVideo(video) {
        if(!this.video) {
            this.video = document.createElement("video");
            this.video.loop = true;
            this.video.muted = true;
            this.video.autoplay = true;
            this.video.onload = () => {
                this.video.play();
            }
        }
        this.isVideo = true;
        this.video.src = video;
        this.video.play();
        this.width = this.video.videoWidth;
        this.height = this.video.videoHeight;
        this.update();
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, self.gl.LINEAR);
    }

    update() {
        const self = this;    
        if(this.isVideo && this.video != null) {
            this.gl.activeTexture(this.gl.TEXTURE0 + this.slot);
            const level = 0;
            const internalFormat = self.gl.RGBA;
            const srcFormat = self.gl.RGBA;
            const srcType = self.gl.UNSIGNED_BYTE;
            self.gl.bindTexture(self.gl.TEXTURE_2D, self.texture);
            self.gl.texImage2D(
                self.gl.TEXTURE_2D,
                level,
                internalFormat,
                srcFormat,
                srcType,
                this.video
            );
        } else {
            this.gl.activeTexture(this.gl.TEXTURE0 + this.slot);
            self.gl.bindTexture(self.gl.TEXTURE_2D, self.texture);
        }
    }

    /**
     * Bind texture to given slot
     * @param {number} slot 
     * @returns {Texture2D} this reference
     */
    bind(slot){
        slot = typeof(slot) != "undefined" ? slot : this.slot;
        this.slot = slot;
        this.gl.activeTexture(this.gl.TEXTURE0 + slot);
        this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
        return this;
    }

    unbind(){
        this.gl.activeTexture(this.gl.TEXTURE0 + this.slot);
        this.gl.bindTexture(this.gl.TEXTURE_2D, null);
    }
}

export class FrameBuffer {
    /**
     * Initialize framebuffer
     * @param {Engine} engine 
     * @param {Array<Texture2D>} texture 
     * @param {boolean?} hasDepth
     */
    constructor(engine, textures, hasDepth){
        const ctx = engine.getContext();
        this.gl = ctx;
        this.frameBuffer = this.gl.createFramebuffer();
        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, this.frameBuffer);
        this.textures = textures;
        this.buffers = [];
        for(let i = 0; i < textures.length; i++ ){
            let texture = textures[i];
            let attachment = this.gl.COLOR_ATTACHMENT0 + i;
            if(texture.depth){
                attachment = this.gl.DEPTH_ATTACHMENT;
            } else this.buffers.push(attachment);
            this.gl.framebufferTexture2D(this.gl.FRAMEBUFFER, attachment, this.gl.TEXTURE_2D, texture.texture, texture.level);
        }
    }

    /**
     * Bind framebuffer
     */
    bind(){
        const gl = this.gl;
        this.textures.forEach( texture => {
            texture.unbind();
        });
        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, this.frameBuffer);
        this.gl.drawBuffers(this.buffers);
    }
}

export class AttributeDefinition {
    /**
     * Create attribute definition
     * @param {Engine} engine
     * @param {number} target
     * @param {Array<{attribute: Attribute, size: number, offset: number, stride: number}>} attributes 
     */
    constructor(engine, target, attributes){
        this.gl = engine.getContext();
        this.target = target || this.gl.ARRAY_BUFFER;
        this.attributes = attributes;
    }

    /**
     * Define vertex attribute
     * @param {{attribute: Attribute, size: number, offset: number, stride: number}} def attribute definition
     */
    defineAttribute(def){
        this.attributes.push(def);
    }

    bind1(){
        for(let i = 0; i<this.attributes.length; i++){
            const {attribute} = this.attributes[i];
            this.gl.enableVertexAttribArray(attribute.location);
        }
    }

    bind2(){
        for(let i = 0; i<this.attributes.length; i++){
            const {attribute, size, offset, stride} = this.attributes[i];
            this.gl.vertexAttribPointer(attribute.location, size, this.gl.FLOAT, false, stride, offset);
        }
    }

    bind(){
        for(let i = 0; i < this.attributes.length; i++){
            const {attribute, size, offset, stride} = this.attributes[i];
            this.gl.enableVertexAttribArray(attribute.location);
            this.gl.vertexAttribPointer(attribute.location, size, this.gl.FLOAT, false, stride, offset)
        }
    }
}

export class Material {
    /**
     * Initialize material
     * @param {Engine} engine 
     * @param {{
     *  diffuse: Texture2D?,
     *  normal: Texture2D?,
     *  pbr: Texture2D?,
     *  indices: Array<number>?,
     *  diffuseK: Array<number>?,
     *  specularK: Array<number>?,
     *  alphaK: number?
     * }} params 
     */
    constructor(engine, params){
        this.gl = engine.getContext();
        this.diffuse = params.diffuse || new Texture2D(engine, { width: 1, height: 1, data: new Uint8Array([255, 255, 255, 255])});
        this.normal = params.normal || new Texture2D(engine, { width: 1, height: 1, data: new Uint8Array([127, 127, 127, 255])});
        this.pbr = params.normal || new Texture2D(engine, { width: 1, height: 1, data: new Uint8Array([127, 127, 127, 255])});
        this.indices = params.indices || [];
        this.diffuseK = typeof(params.diffuseK) != "undefined" ? params.diffuseK : [1, 1, 1];
        this.specularK = typeof(params.specularK) != "undefined" ? params.specularK : [1, 1, 1];
        this.alphaK = typeof(params.alphaK) == "undefined" ? 1 : params.alphaK;
    }

    /**
     * Bind textures
     */
    bind(){
        this.diffuse && this.diffuse.bind(0);
        this.normal && this.normal.bind(1);
        this.pbr && this.pbr.bind(2);
    }

    /**
     * Get indices
     * @returns {Array<[pivot, length]>} indices 
     */
    getIndices(){
        return this.indices;
    }
}

class Drawable {
    /**
     * Create drawable
     * @param {Engine} engine 
     */
    constructor(engine){
        this.gl = engine.getContext();
    }

    /**
     * Is complete
     * @returns {boolean}
     */
    isComplete(){
        return false;
    }

    /**
     * Set vertex buffer
     * @param {VertexBuffer} buffer 
     */
    setVertexBuffer(buffer){
        this.vertexBuffer = buffer;
    }

    /**
     * Set index buffer
     * @param {IndexBuffer} buffer 
     */
    setIndexBuffer(buffer){
        this.indexBuffer = buffer;
    }

    /**
     * Get vertex buffer
     * @returns {VertexBuffer}
     */
    getVertexBuffer(){
        return this.vertexBuffer;
    }

    /**
     * Get index buffer
     * @returns {IndexBuffer}
     */
    getIndexBuffer(){
        return this.indexBuffer;
    }

    /**
     * Draw drawable
     * @param {Engine} engine 
     */
    draw(engine){

    }
}

export class Mesh extends Drawable {
    /**
     * Initialize mesh
     * @param {Engine} engine 
     * @param {String} path
     */
    constructor(engine, path){
        super(engine);
        this.materials = {};
        this.path = path;
        this.indexes = [];
        this.complete = false;
    }

    /**
     * Initialize object 
     * @param {Engine} engine 
     * @param {AttributeDefinition} attributes 
     * @returns {Promise<Mesh>} mesh
     */
    async init(engine){
        const self = this;
        const attributes = engine.getAttributes();
        let dir = this.path.split("/");
        dir.pop();
        dir = dir.join("/") + "/";
        return new Promise( (resolve) => {
            var xhr = new XMLHttpRequest();
            xhr.onreadystatechange = () => {
                if(xhr.readyState == 4 && xhr.status == 200){
                    var lines = xhr.responseText.split("\n");
                    var vBuffer = [];
                    var iBuffer = [];
                    var vertices = [];
                    var texcoords = [];
                    var normals = [];
                    var idxCounter = 0;
                    var Parser = {
                        mtllib: (line) => {
                            const mtlXhr = new XMLHttpRequest();
                            mtlXhr.onreadystatechange = () => {
                                if(mtlXhr.readyState == 4 && mtlXhr.status == 200){
                                    self.parseMaterialFile(engine, dir, mtlXhr.responseText);
                                }
                            }
                            mtlXhr.open("GET", dir + line.trim());
                            mtlXhr.send();
                        },
                        v: (line) => { vertices.push(line.split(" ").map( o => parseFloat(o) )) },
                        vt: (line) => { texcoords.push(line.split(" ").map( o => parseFloat(o) )) },
                        vn: (line) => { normals.push(line.split(" ").map( o => parseFloat(o) )) },
                        f: (line) => {
                            var parts = line.split(" ");
                            parts.forEach((part, idx) => {
                                var p = part.split("/");
                                var normal = [1, 0, 0];
                                var tx = [0, 0];
                                var vtx = [0, 0, 0];
                                if(p.length >= 3){
                                    normal = normals[parseInt(p[2].trim()) - 1];
                                }
                                if(p.length >= 2){
                                    tx = texcoords[parseInt(p[1].trim()) - 1];
                                }
                                if(p.length >= 1){
                                    vtx = vertices[parseInt(p[0].trim()) - 1];
                                }
                                vBuffer.push(vtx[0], vtx[1], vtx[2], tx[0], tx[1], normal[0], normal[1], normal[2]);
                                if (idx < 3) {
                                    iBuffer.push(idxCounter++);
                                } else {
                                    iBuffer.push(idxCounter - 3);
                                    iBuffer.push(idxCounter - 1);
                                    iBuffer.push(idxCounter);
                                    idxCounter++;
                                }
                            });
                        },
                        usemtl: (line) => {
                            self.indexes.push({ mtl: line.trim(), pivot: iBuffer.length });
                        }
                    };
                    lines.forEach( (line) => {
                        var parts = line.split(" ");
                        var what = parts.shift();
                        var rest = parts.join(" ");
                        if(what in Parser){
                            Parser[what](rest);
                        }
                    });
                    self.indexes.push({ mtl: null, pivot: iBuffer.length });
                    for(var i=0; i<self.indexes.length - 1; i++){
                        var idx = self.indexes[i];
                        var next = self.indexes[i + 1];
                        if(!(idx.mtl in self.materials)){
                            self.materials[idx.mtl] = new Material(engine, {});
                        }
                        self.materials[idx.mtl].indices.push([idx.pivot, next.pivot - idx.pivot]);
                    }
                    self.setIndexBuffer(new IndexBuffer(engine, iBuffer));
                    self.setVertexBuffer(new VertexBuffer(engine, vBuffer, attributes));
                    self.iBuffer = iBuffer;
                    self.vBuffer = vBuffer;
                    self.complete = true;
                    resolve(self);
                }
            };
            xhr.open("GET", self.path);
            xhr.send();
        });
    }

    /**
     * Parse material file
     * @param {Engine} engine 
     * @param {string} dir
     * @param {string} content 
     */
    parseMaterialFile(engine, dir, content){
        const lines = content.split("\n").map( o => o.trim() ).filter( o => o.length > 0 );
        const self = this;
        let material = null;
        const Parser = {
            newmtl: (mtl) => { material = mtl; },
            map_Kd: (path) => { self.assignMaterial(engine, material, "diffuse", dir + path); },
            map_Ka: (path) => { self.assignMaterial(engine, material, "diffuse", dir + path); },
            map_Ks: (path) => { self.assignMaterial(engine, material, "pbr", dir + path); },
            map_bump: (path) => { self.assignMaterial(engine, material, "normal", dir + path); },
            Kd: (color) => { self.assignColor(engine, material, "diffuseK", color); },
            Ka: (color) => { self.assignColor(engine, material, "diffuseK", color); },
            Ks: (color) => { self.assignColor(engine, material, "specularK", color); },
            d: (color) => { self.assignColor(engine, material, "alphaK", color); }
        };

        lines.forEach( line => {
            let parts = line.split(" ");
            let what = parts.shift();
            if(what in Parser){
                Parser[what](parts.join(" "));
            }
        });
    }

    /**
     * Assign material field
     * @param {Engine} engine
     * @param {*} material 
     * @param {*} field 
     * @param {*} path 
     */
    assignMaterial(engine, material, field, path){
        if(!(material in this.materials)){
            this.materials[material] = new Material(engine, { [field] : new Texture2D(engine, { url: path }) });
        } else {
            this.materials[material][field] = new Texture2D(engine, { url: path });
        }
    }

    /**
     * Assign material color
     * @param {Engine} engine 
     * @param {string} material 
     * @param {string} field 
     * @param {string} color 
     */
    assignColor(engine, material, field, color){
        if(field == "alpha") color = parseFloat(color);
        else color = color.replace(/\t/ig, " ").split(" ").map(o => o.trim()).filter( o => o.length > 0 ).map(o => parseFloat(o));
        if(!(material in this.materials)){
            this.materials[material] = new Material(engine, { [field] : color });
        } else {
            this.materials[material][field] = color;
        }
    }


    /**
     * Is complete
     * @returns {boolean}
     */
    isComplete(){
        return this.complete;
    }

    /**
     * Get materials
     * @returns {Map<String, Material>} materials
     */
    getMaterials(){
        return this.materials;
    }

    /**
     * Draw mesh
     * @param {Engine} engine 
     */
    draw(engine){
        if(!this.complete) return false;
        const self = this;
        let materials = this.getMaterials();
        for(let mtl in materials){
            let material = materials[mtl];
            material.bind();
            material.indices.forEach( info => {
                engine.draw(self.getVertexBuffer(), self.getIndexBuffer(), info[1], info[0] * 2);
            });
        }
    }
}

export class Quad extends Drawable {
    /**
     * Create new 2D quad
     * @param {Engine} engine 
     * @param {Attribute} attributes 
     */
    constructor(engine){
        super(engine);
        this.setVertexBuffer(new VertexBuffer(engine, [
            -1.0,   -1.0,   0,      0.0,    0.0,    1.0,    0.0,   0.0,
            1.0,    -1.0,   0,      1.0,    0.0,    1.0,    0.0,   0.0,
            1.0,     1.0,   0,      1.0,    1.0,    1.0,    0.0,   0.0,
            -1.0,    1.0,   0,      0.0,    1.0,    1.0,    0.0,   0.0,
        ], engine.getAttributes()));

        this.setIndexBuffer(new IndexBuffer(engine, [
            0, 1, 2,    0, 2, 3
        ]));
    }

    /**
     * Is complete
     * @returns {boolean}
     */
    isComplete(){
        return true;
    }

    /**
     * Draw quad
     * @param {Engine} engine 
     */
    draw(engine){
        engine.draw(this.getVertexBuffer(), this.getIndexBuffer(), 6, 0);
    }
}

/**
 * OnFrameCallback
 * @callback onFrameCallback
 * @param {engine: Engine, deltaTime: number} engine
 */

export class Engine {
    /**
     * Initialize engine
     * @param {HTMLCanvasElement} output 
     */
    constructor(output){
        this.canvas = output;
        this.gl = output.getContext("webgl2");
        const ext1 = this.gl.getExtension("OES_texture_float_linear");
        const ext2 = this.gl.getExtension("OES_texture_float");
        if(ext1 === null && ext2 === null){
            alert("Your browser doesn't support floating point textures!!!");
        }
        this.extensions = this.gl.getSupportedExtensions();
        console.log("Extensions: " , this.extensions);
        this.lastTime = Date.now();
        this.gl.enable(this.gl.DEPTH_TEST);
    }

    /**
     * Get WebGL context
     * @returns {WebGL2RenderingContext} context
     */
    getContext(){
        return this.gl;
    }

    /**
     * Clear color buffer
     * @param {number} r 
     * @param {number} g 
     * @param {number} b 
     */
    clearColor(r, g, b){
        this.gl.clearColor(r, g, b, 1.0);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);
        this.gl.enable(this.gl.BLEND);
        //this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);
    }

    /**
     * Create attributes
     * @param {ShaderProgram} program
     */
    createAttributes(program){
        const stride = 8 * Float32Array.BYTES_PER_ELEMENT;
        this.attributes = new AttributeDefinition( this, this.gl.ARRAY_BUFFER, [
            { attribute: program.getAttribute("vertexPosition"), size: 3, offset: 0, stride: stride },
            { attribute: program.getAttribute("vertexTexcoord"), size: 2, offset: 3 * Float32Array.BYTES_PER_ELEMENT, stride: stride },
            { attribute: program.getAttribute("vertexNormal"), size: 3, offset: 5 * Float32Array.BYTES_PER_ELEMENT, stride: stride }
        ] );
    }

    /**
     * Get attributes
     * @returns {AttributeDefinition}
     */
    getAttributes(){
        return this.attributes;
    }

    /**
     * Get active program
     * @returns {ShaderProgram}
     */
    getActiveProgram(){
        return this.activeProgram;
    }

    /**
     * Use program
     * @param {ShaderProgram} program 
     */
    useProgram(program){
        this.activeProgram = program;
        program.use();
    }

    /**
     * Set on frame callback
     * @param {onFrameCallback} callback 
     */
    onFrame(callback){
        this.onFrameCallback = callback;
    }

    /**
     * Draw array buffer
     * @param {GlBuffer} vertexBuffer 
     * @param {GlBuffer} indexBuffer
     * @param {number} count 
     * @param {number?} offset 
     */
    draw(vertexBuffer, indexBuffer, count, offset){
        vertexBuffer.bind();
        indexBuffer.bind();
        this.gl.drawElements(this.gl.TRIANGLES, count, this.gl.UNSIGNED_SHORT, offset);
    }

    /**
     * Render scene
     */
    render(){
        const start = Date.now();
        const delta = Date.now() - this.lastTime;
        if(this.onFrameCallback){
            this.onFrameCallback(this, delta / 1000);
        }
        this.frameTime = Date.now() - start;
        this.lastTime = this.frameTime + start;
    }

    /**
     * Begin rendering
     */
    beginRendering(){
        const self = this;
        window.requestAnimationFrame( ()=> {
            self.render();
            self.beginRendering();
        });
    }

    /**
     * Set render target
     * @param {FrameBuffer|null} frameBuffer 
     */
    setRenderTarget(frameBuffer){
        frameBuffer = frameBuffer || null;
        if(frameBuffer == null){
            this.gl.viewport(0, 0, this.canvas.width, this.canvas.height)
            this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
        } else {
            this.gl.viewport(0, 0, frameBuffer.textures[0].width, frameBuffer.textures[0].height);
            frameBuffer.bind();
        }
    }
}