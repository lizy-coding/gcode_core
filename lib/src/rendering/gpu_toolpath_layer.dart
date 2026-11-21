import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../core/gcode_bounds.dart';
import '../core/gcode_style.dart';
import '../models/exposure_bitmap.dart';
import '../models/toolpath_segment.dart';
import '../models/machining_preview.dart';
import '../models/preview_timeline.dart';
import 'frame_uniform_budget.dart';
import 'toolpath_geometry.dart';
import 'toolpath_viewport.dart';

/// Optional counters of renderer work submitted by the CPU.
///
/// These counters do not measure GPU time or native memory reclamation. Keep
/// one instance for the lifetime of a canvas to compare loading and playback.
class GcodeRenderStats {
  int _textureUploads = 0;
  int _textureUploadBytes = 0;
  int get textureUploads => _textureUploads;
  int get textureUploadBytes => _textureUploadBytes;

  int _uniformBufferCreations = 0;
  int _uniformBufferReservedBytes = 0;

  /// Cumulative number of rotating frame-uniform buffers created.
  int get uniformBufferCreations => _uniformBufferCreations;

  /// Cumulative byte capacity requested for those buffers, across all slots.
  int get uniformBufferReservedBytes => _uniformBufferReservedBytes;

  int _geometryBuilds = 0;
  int _vertexUploadBytes = 0;
  int _compositedFrames = 0;
  int _surfaceCreations = 0;
  int _surfaceResizes = 0;
  int _resourceSetsCreated = 0;
  int _resourceSetsCleared = 0;

  int get geometryBuilds => _geometryBuilds;
  int get vertexUploadBytes => _vertexUploadBytes;
  int get compositedFrames => _compositedFrames;
  int get surfaceCreations => _surfaceCreations;
  int get surfaceResizes => _surfaceResizes;
  int get resourceSetsCreated => _resourceSetsCreated;
  int get resourceSetsCleared => _resourceSetsCleared;
  int get activeResourceSets => _resourceSetsCreated - _resourceSetsCleared;
}

/// GPU scene: paths, grid, origin and moving markers share one surface.
class GpuToolpathLayer extends StatefulWidget {
  const GpuToolpathLayer(
      {super.key,
      required this.segments,
      required this.bounds,
      required this.progress,
      required this.style,
      this.bitmap,
      this.scene,
      this.timeline,
      this.onReady,
      this.onError,
      this.stats});
  final ExposureBitmap? bitmap;
  final MachiningPreview? scene;
  final PreviewTimeline? timeline;
  final List<ToolpathSegment> segments;
  final GcodeBounds? bounds;
  final double progress;
  final GcodeStyle style;
  final VoidCallback? onReady;
  final ValueChanged<Object>? onError;
  final GcodeRenderStats? stats;
  @override
  State<GpuToolpathLayer> createState() => _GpuToolpathLayerState();
}

class _GpuToolpathLayerState extends State<GpuToolpathLayer> {
  _GpuResources? resources;
  Object? error;
  bool _presented = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant GpuToolpathLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.segments, widget.segments)) _presented = false;
  }

  Future<void> _initialize() async {
    try {
      final library = await gpu.ShaderLibrary.fromAsset(
          'packages/gcode_core/shaders/toolpath.shaderbundle');
      if (library == null) throw StateError('Invalid toolpath shader bundle');
      final pipeline = gpu.gpuContext.createRenderPipeline(
          library['ToolpathVertex']!, library['ToolpathFragment']!);
      final guides = gpu.gpuContext.createRenderPipeline(
          library['GuidesVertex']!, library['GuidesFragment']!);
      final bitmapPipeline = widget.bitmap == null && widget.scene == null
          ? null
          : gpu.gpuContext.createRenderPipeline(
              library['BitmapVertex']!, library['BitmapFragment']!);
      if (mounted)
        setState(() => resources =
            _GpuResources(pipeline, guides, bitmapPipeline, widget));
    } catch (e) {
      debugPrint('GCODE_GPU_INIT_FAILED $e');
      if (mounted) {
        setState(() => error = e);
        widget.onError?.call(e);
      }
    }
  }

  void _failed(Object failure) {
    if (error != null) return;
    debugPrint('GCODE_GPU_RENDER_FAILED $failure');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        resources?.clear();
        setState(() {
          resources = null;
          error = failure;
        });
        widget.onError?.call(failure);
      }
    });
  }

  void _ready() {
    if (_presented || error != null) return;
    _presented = true;
    final presentedSegments = widget.segments;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          error == null &&
          identical(presentedSegments, widget.segments)) {
        widget.onReady?.call();
      }
    });
  }

  @override
  void dispose() {
    resources?.clear();
    resources = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
          child: Text('GPU 绘制不可用\n$error', textAlign: TextAlign.center));
    }
    if (resources == null)
      return const Center(child: CircularProgressIndicator());
    return CustomPaint(
        painter: _GpuImageCompositor(resources!, widget,
            MediaQuery.devicePixelRatioOf(context), _failed, _ready));
  }
}

class _GpuResources {
  _GpuResources(
      this.pipeline, this.guides, this.bitmapPipeline, GpuToolpathLayer input)
      : stats = input.stats {
    final data = Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 1]);
    quad = gpu.BufferView(
        gpu.gpuContext.createDeviceBufferWithCopy(ByteData.sublistView(data)),
        offsetInBytes: 0,
        lengthInBytes: data.lengthInBytes);
    final operations = input.scene?.operations;
    final vectorDraws = operations == null
        ? (input.bitmap == null ? 2 : 0)
        : operations.whereType<VectorPreviewOperation>().length +
            (input.segments.isEmpty ? 0 : 1);
    final bitmapDraws = operations == null
        ? (input.bitmap == null ? 0 : 1)
        : operations.whereType<BitmapPreviewOperation>().length;
    uniforms = _FrameUniforms(pipeline, guides, bitmapPipeline,
        vectorDraws: vectorDraws, bitmapDraws: bitmapDraws);
    stats?._uniformBufferCreations++;
    stats?._uniformBufferReservedBytes += uniforms!.reservedBytes;
    stats?._resourceSetsCreated++;
  }
  final GcodeRenderStats? stats;
  bool _cleared = false;
  final gpu.RenderPipeline pipeline;
  final gpu.RenderPipeline guides;
  final gpu.RenderPipeline? bitmapPipeline;
  final textures = Map<ExposureBitmap, gpu.Texture>.identity();
  late final gpu.BufferView quad;
  _FrameUniforms? uniforms;
  ToolpathViewport? viewport;
  GcodeBounds? suppliedBounds;
  gpu.GpuImageSurface? surface;
  gpu.BufferView? vertices;
  List<ToolpathSegment>? segments;
  GcodeBounds? bounds;
  Size? size;
  double? width;
  int vertexCount = 0;
  List<int> prefixVertexCounts = const [0];
  void clear() {
    if (_cleared) return;
    _cleared = true;
    stats?._resourceSetsCleared++;
    textures.clear();
    uniforms = null;
    surface = null;
    vertices = null;
    segments = null;
    viewport = null;
    suppliedBounds = null;
    bounds = null;
    size = null;
    width = null;
    vertexCount = 0;
    prefixVertexCounts = const [0];
  }

  void prepare(GpuToolpathLayer input, Size newSize, double dpr) {
    final image = input.bitmap;
    if (image == null) {
      _preparePath(input, newSize);
    } else {
      if (viewport == null || size != newSize) {
        viewport = ToolpathViewport(image.bounds, newSize);
        size = newSize;
      }
    }
    final w = math.max(1, (newSize.width * dpr).ceil());
    final h = math.max(1, (newSize.height * dpr).ceil());
    if (surface == null) {
      surface = gpu.gpuContext
          .createImageSurface(w, h, format: gpu.PixelFormat.r8g8b8a8UNormInt);
      stats?._surfaceCreations++;
    }
    if (surface!.width != w || surface!.height != h) {
      surface!.resize(w, h);
      stats?._surfaceResizes++;
    }
  }

  gpu.Texture textureFor(ExposureBitmap image) {
    final cached = textures[image];
    if (cached != null) return cached;
    try {
      final texture = gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate, image.width, image.height,
          format: gpu.PixelFormat.r8UNormInt, enableRenderTargetUsage: false);
      texture.overwrite(ByteData.sublistView(image.samples));
      textures[image] = texture;
      stats?._textureUploads++;
      stats?._textureUploadBytes += image.samples.length;
      return texture;
    } catch (error) {
      throw StateError('无法上传曝光纹理（${image.width} × ${image.height}）: $error');
    }
  }

  void _preparePath(GpuToolpathLayer input, Size newSize) {
    final maxWidth = [
      input.style.rapidMove.width,
      input.style.linearMove.width,
      input.style.rapidBackground.width,
      input.style.linearBackground.width
    ].reduce(math.max);
    final changed = !identical(segments, input.segments) ||
        suppliedBounds?.minX != input.bounds?.minX ||
        suppliedBounds?.minY != input.bounds?.minY ||
        suppliedBounds?.maxX != input.bounds?.maxX ||
        suppliedBounds?.maxY != input.bounds?.maxY;
    if (changed || bounds == null) {
      bounds = input.bounds ?? ToolpathViewport.measure(input.segments);
      suppliedBounds = input.bounds;
    }
    if (changed || size != newSize || width != maxWidth) {
      viewport = ToolpathViewport(bounds!, newSize);
      final nextGeometry =
          ToolpathGeometry.build(input.segments, bounds!, newSize, maxWidth);
      stats?._geometryBuilds++;
      stats?._vertexUploadBytes += nextGeometry.vertices.lengthInBytes;
      vertexCount = nextGeometry.vertexCount;
      vertices = vertexCount == 0
          ? null
          : gpu.BufferView(
              gpu.gpuContext.createDeviceBufferWithCopy(
                  ByteData.sublistView(nextGeometry.vertices)),
              offsetInBytes: 0,
              lengthInBytes: nextGeometry.vertices.lengthInBytes);
      prefixVertexCounts = nextGeometry.prefixVertexCounts;
      segments = input.segments;
      size = newSize;
      width = maxWidth;
    }
  }
}

class _UniformBlock {
  _UniformBlock(this.slot) : data = ByteData(slot.sizeInBytes!);

  final gpu.UniformSlot slot;
  final ByteData data;
  final _offsets = <String, int>{};

  void vec4(String member, double x, double y, double z, double w) {
    final offset = _offsets[member] ??= slot.getMemberOffsetInBytes(member)!;
    data
      ..setFloat32(offset, x, Endian.host)
      ..setFloat32(offset + 4, y, Endian.host)
      ..setFloat32(offset + 8, z, Endian.host)
      ..setFloat32(offset + 12, w, Endian.host);
  }

  void color(String member, Color color) {
    vec4(member, color.r, color.g, color.b, color.a);
  }
}

class _FrameUniforms {
  _FrameUniforms(gpu.RenderPipeline path, gpu.RenderPipeline guides,
      gpu.RenderPipeline? bitmap,
      {required int vectorDraws, required int bitmapDraws})
      : guideFrame =
            _UniformBlock(guides.vertexShader.getUniformSlot('GuideFrame')),
        guideInfo =
            _UniformBlock(guides.fragmentShader.getUniformSlot('GuideInfo')),
        pathFrame =
            _UniformBlock(path.vertexShader.getUniformSlot('FrameInfo')),
        pathPaint =
            _UniformBlock(path.fragmentShader.getUniformSlot('PaintInfo')),
        bitmapFrame = bitmap == null
            ? null
            : _UniformBlock(bitmap.vertexShader.getUniformSlot('BitmapFrame')),
        bitmapScan = bitmap == null
            ? null
            : _UniformBlock(bitmap.fragmentShader.getUniformSlot('ScanInfo')),
        exposure = bitmap?.fragmentShader.getUniformSlot('exposure') {
    final context = gpu.gpuContext;
    alignment = context.minimumUniformByteAlignment;
    final capacity = frameUniformCapacity(
      alignment: alignment,
      guideVertexBytes: guideFrame.data.lengthInBytes,
      guideFragmentBytes: guideInfo.data.lengthInBytes,
      pathVertexBytes: pathFrame.data.lengthInBytes,
      pathFragmentBytes: pathPaint.data.lengthInBytes,
      bitmapVertexBytes: bitmapFrame?.data.lengthInBytes ?? 0,
      bitmapFragmentBytes: bitmapScan?.data.lengthInBytes ?? 0,
      vectorDraws: vectorDraws,
      bitmapDraws: bitmapDraws,
    );
    // The SDK allocates an extra retained block on each frame that spills.
    // A whole frame fits in one block regardless of playback position.
    host = context.createHostBuffer(blockLengthInBytes: capacity);
  }

  final _UniformBlock guideFrame, guideInfo, pathFrame, pathPaint;
  final _UniformBlock? bitmapFrame, bitmapScan;
  final gpu.UniformSlot? exposure;
  late final int alignment;
  late final gpu.HostBuffer host;
  int _usedBytes = 0;
  int get reservedBytes => host.blockLengthInBytes * host.frameCount;
  gpu.BufferView? _guideView;
  gpu.BufferView? _pathView;

  void begin() {
    host.reset();
    _usedBytes = 0;
    _guideView = null;
    _pathView = null;
  }

  void bindViewport(gpu.RenderPass pass, Size size, {required bool guides}) {
    final block = guides ? guideFrame : pathFrame;
    var view = guides ? _guideView : _pathView;
    if (view == null) {
      block.vec4('viewport', size.width, size.height, 0, 0);
      view = _upload(block);
      if (guides) {
        _guideView = view;
      } else {
        _pathView = view;
      }
    }
    pass.bindUniform(block.slot, view);
  }

  void bind(gpu.RenderPass pass, _UniformBlock block) {
    pass.bindUniform(block.slot, _upload(block));
  }

  gpu.BufferView _upload(_UniformBlock block) {
    _usedBytes += alignedUniformBytes(block.data.lengthInBytes, alignment);
    if (_usedBytes > host.blockLengthInBytes) {
      throw StateError('Frame uniform capacity exceeded');
    }
    // emplace copies synchronously into the current frame's GPU buffer.
    return host.emplace(block.data);
  }
}

class _GpuImageCompositor extends CustomPainter {
  _GpuImageCompositor(
      this.resources, this.input, this.dpr, this.failed, this.ready);
  final _GpuResources resources;
  final GpuToolpathLayer input;
  final double dpr;
  final void Function(Object) failed;
  final VoidCallback ready;

  void _drawGuides(
      gpu.RenderPass pass, _FrameUniforms uniforms, Size size, double layer,
      [Offset? head]) {
    final viewport = resources.viewport!;
    final plot = viewport.plot;
    final grid = viewport.gridOrigin;
    final origin = viewport.project(0, 0);
    final style = input.style;
    pass.clearBindings();
    pass.bindPipeline(resources.guides);
    pass.bindVertexBuffer(resources.quad);
    uniforms.bindViewport(pass, size, guides: true);
    final guide = uniforms.guideInfo
      ..vec4('viewport', size.width, size.height, dpr, layer)
      ..vec4('plot', plot.left, plot.top, plot.right, plot.bottom)
      ..vec4('grid_origin', grid.dx, grid.dy, style.grid.width, 0)
      ..vec4('origin', origin.dx, origin.dy, style.origin.width,
          head == null ? 0.0 : 1.0)
      ..vec4('head', head?.dx ?? 0, head?.dy ?? 0, 5, 10)
      ..color('grid_color', style.grid.color)
      ..color('origin_color', style.origin.color)
      ..color('origin_dot', style.originDotColor)
      ..color('head_color', style.toolHeadColor)
      ..color('glow_color', style.toolHeadGlowColor);
    uniforms.bind(pass, guide);
    pass.draw(6);
  }

  void _drawBitmap(gpu.RenderPass pass, _FrameUniforms uniforms, Size size,
      ExposureBitmap image, double progress) {
    final pipeline = resources.bitmapPipeline!;
    final viewport = resources.viewport!;
    final origin = viewport.project(image.origin.dx, image.origin.dy);
    final column = image.columnSpan * viewport.scale;
    final row = image.rowSpan * viewport.scale;
    pass.clearBindings();
    pass.bindPipeline(pipeline);
    pass.bindVertexBuffer(resources.quad);
    final frame = uniforms.bitmapFrame!
      ..vec4('origin_viewport', origin.dx, origin.dy, size.width, size.height)
      ..vec4('axes', column.dx, -column.dy, row.dx, -row.dy);
    uniforms.bind(pass, frame);
    final scan = uniforms.bitmapScan!
      ..vec4('scan', image.width.toDouble(), image.height.toDouble(),
          progress * image.height, image.firstRowRightToLeft ? 1.0 : 0.0);
    uniforms.bind(pass, scan);
    pass.bindTexture(uniforms.exposure!, resources.textureFor(image));
    pass.draw(6);
  }

  void _drawPath(gpu.RenderPass pass, _FrameUniforms uniforms, Size size,
      int firstSegment, double segmentPosition,
      {bool background = false}) {
    final prefix = resources.prefixVertexCounts;
    final firstVertex = prefix[firstSegment];
    final drawCount = prefix[segmentPosition.ceil()] - firstVertex;
    if (drawCount == 0) return;
    pass.clearBindings();
    pass.bindPipeline(resources.pipeline);
    final vertices = resources.vertices!;
    final stride = vertices.lengthInBytes ~/ resources.vertexCount;
    pass.bindVertexBuffer(gpu.BufferView(vertices.buffer,
        offsetInBytes: vertices.offsetInBytes + firstVertex * stride,
        lengthInBytes: drawCount * stride));
    uniforms.bindViewport(pass, size, guides: false);
    final style = input.style;
    final paint = uniforms.pathPaint
      ..vec4('progress_layer', segmentPosition, background ? 0.0 : 1.0, dpr, 0)
      ..color('rapid_color', style.rapidMove.color)
      ..color('linear_color', style.linearMove.color)
      ..color('rapid_background', style.rapidBackground.color)
      ..color('linear_background', style.linearBackground.color)
      ..vec4('widths', style.rapidMove.width, style.linearMove.width,
          style.rapidBackground.width, style.linearBackground.width);
    uniforms.bind(pass, paint);
    pass.draw(drawCount);
  }

  Offset? _drawForeground(
      gpu.RenderPass pass, _FrameUniforms uniforms, Size size) {
    if (input.progress <= 0) return null;
    final scene = input.scene;
    final viewport = resources.viewport!;
    if (scene == null) {
      final bitmap = input.bitmap;
      if (bitmap != null) {
        _drawBitmap(pass, uniforms, size, bitmap, input.progress);
        return null;
      }
      _drawPath(
          pass, uniforms, size, 0, input.progress * input.segments.length);
      return viewport.toolHead(input.segments, input.progress);
    }

    final timeline = input.timeline;
    final timedPosition =
        timeline?.positionAt(input.progress * timeline.totalSeconds);
    final weightedPosition = input.progress * scene.totalWeight;
    var elapsed = 0.0;
    var firstSegment = 0;
    Offset? head;
    for (var i = 0; i < scene.operations.length; i++) {
      final operation = scene.operations[i];
      final end = elapsed + operation.weight;
      final local = timedPosition != null || weightedPosition >= end
          ? 1.0
          : (weightedPosition - elapsed) / operation.weight;
      final isTarget = timedPosition == null
          ? weightedPosition <= end
          : i == timedPosition.operationIndex;
      final timedLocal = isTarget ? timedPosition?.localPosition : null;
      switch (operation) {
        case VectorPreviewOperation():
          final count = operation.segments.length;
          final segmentPosition = timedLocal ?? local * count;
          _drawPath(pass, uniforms, size, firstSegment,
              firstSegment + segmentPosition);
          if (isTarget) {
            head = viewport.toolHeadAt(operation.segments, segmentPosition);
          }
          firstSegment += count;
        case BitmapPreviewOperation():
          final bitmapProgress = timedLocal ?? local;
          if (bitmapProgress > 0) {
            _drawBitmap(pass, uniforms, size, operation.image, bitmapProgress);
          }
      }
      if (isTarget) break;
      elapsed = end;
    }
    return head;
  }

  // Canvas only composites the finished GPU image; it draws no scene geometry.
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 60 || size.height <= 60) return;
    gpu.GpuImageSurfaceFrame? frame;
    try {
      resources.prepare(input, size, dpr);
      frame = resources.surface!.acquireNextFrame();
      final command = gpu.gpuContext.createCommandBuffer();
      final pass = command.createRenderPass(gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(texture: frame.colorTexture)));
      pass.setColorBlendEnable(true);
      pass.setColorBlendEquation(gpu.ColorBlendEquation());
      final uniforms = resources.uniforms!..begin();
      _drawGuides(pass, uniforms, size, 0);
      if (resources.vertexCount > 0) {
        _drawPath(pass, uniforms, size, 0, input.segments.length.toDouble(),
            background: true);
      }
      final head = _drawForeground(pass, uniforms, size);
      _drawGuides(pass, uniforms, size, 1, head);
      frame.present(command);
      command.submit();
      final ui.Image image = resources.surface!.currentImage!;
      try {
        canvas.drawImageRect(
            image,
            Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            Offset.zero & size,
            Paint());
      } finally {
        image.dispose();
      }
      resources.stats?._compositedFrames++;
      ready();
    } catch (e) {
      frame?.discard();
      failed(e);
    }
  }

  @override
  bool shouldRepaint(covariant _GpuImageCompositor oldDelegate) {
    return !identical(resources, oldDelegate.resources) ||
        !identical(input.segments, oldDelegate.input.segments) ||
        !identical(input.timeline, oldDelegate.input.timeline) ||
        input.bounds != oldDelegate.input.bounds ||
        input.progress != oldDelegate.input.progress ||
        input.style != oldDelegate.input.style ||
        dpr != oldDelegate.dpr;
  }
}
