const std = @import("std");
const warn = std.debug.warn;

const c = @cImport({
    @cDefine("CL_TARGET_OPENCL_VERSION", "110");
    @cInclude("CL/cl.h");
});

var program_src =
    c\\__kernel void square_array(__global int* input_array, __global int* output_array) {
    c\\    int i = get_global_id(0);
    c\\    int value = input_array[i];
    c\\    output_array[i] = value * value;
    c\\}
;

const CLError = error{
    GetPlatformsFailed,
    GetPlatformInfoFailed,
    NoPlatformsFound,
    GetDevicesFailed,
    GetDeviceInfoFailed,
    NoDevicesFound,
    CreateContextFailed,
    CreateCommandQueueFailed,
    CreateProgramFailed,
    BuildProgramFailed,
    CreateKernelFailed,
    SetKernelArgFailed,
    EnqueueNDRangeKernel,
    CreateBufferFailed,
    EnqueueWriteBufferFailed,
    EnqueueReadBufferFailed,
};

fn get_cl_device() CLError!c.cl_device_id {
    var platform_ids: [16]c.cl_platform_id = undefined;
    var platform_count: c.cl_uint = undefined;
    if (c.clGetPlatformIDs(platform_ids.len, &platform_ids, &platform_count) != c.CL_SUCCESS) {
        return CLError.GetPlatformsFailed;
    }
    warn("{} cl platform(s) found:\n", @intCast(u32, platform_count));

    for (platform_ids[0..platform_count]) |id, i| {
        var name: [1024]u8 = undefined;
        var name_len: usize = undefined;
        if (c.clGetPlatformInfo(id, c.CL_PLATFORM_NAME, name.len, &name, &name_len) != c.CL_SUCCESS) {
            return CLError.GetPlatformInfoFailed;
        }
        warn("  platform {}: {}\n", i, name[0..name_len]);
    }

    if (platform_count == 0) {
        return CLError.NoPlatformsFound;
    }

    warn("choosing platform 0...\n");

    var device_ids: [16]c.cl_device_id = undefined;
    var device_count: c.cl_uint = undefined;
    if (c.clGetDeviceIDs(platform_ids[0], c.CL_DEVICE_TYPE_ALL, device_ids.len, &device_ids, &device_count) != c.CL_SUCCESS) {
        return CLError.GetDevicesFailed;
    }
    warn("{} cl device(s) found on platform 0:\n", @intCast(u32, device_count));

    for (device_ids[0..device_count]) |id, i| {
        var name: [1024]u8 = undefined;
        var name_len: usize = undefined;
        if (c.clGetDeviceInfo(id, c.CL_DEVICE_NAME, name.len, &name, &name_len) != c.CL_SUCCESS) {
            return CLError.GetDeviceInfoFailed;
        }
        warn("  device {}: {}\n", i, name[0..name_len]);
    }

    if (device_count == 0) {
        return CLError.NoDevicesFound;
    }

    warn("choosing device 0...\n");

    return device_ids[0];
}

fn run_test(device: c.cl_device_id) CLError!void {
    warn("** running test **\n");

    var ctx = c.clCreateContext(null, 1, &device, null, null, null); // future: last arg is error code
    if (ctx == null) {
        return CLError.CreateContextFailed;
    }
    defer _ = c.clReleaseContext(ctx);

    var command_queue = c.clCreateCommandQueue(ctx, device, 0, null); // future: last arg is error code
    if (command_queue == null) {
        return CLError.CreateCommandQueueFailed;
    }
    defer {
        _ = c.clFlush(command_queue);
        _ = c.clFinish(command_queue);
        _ = c.clReleaseCommandQueue(command_queue);
    }

    var program_src_c: [*c]const u8 = program_src;
    var program = c.clCreateProgramWithSource(ctx, 1, &program_src_c, null, null); // future: last arg is error code
    if (program == null) {
        return CLError.CreateProgramFailed;
    }
    defer _ = c.clReleaseProgram(program);

    if (c.clBuildProgram(program, 1, &device, null, null, null) != c.CL_SUCCESS) {
        return CLError.BuildProgramFailed;
    }

    var kernel = c.clCreateKernel(program, c"square_array", null);
    if (kernel == null) {
        return CLError.CreateKernelFailed;
    }
    defer _ = c.clReleaseKernel(kernel);

    // Create buffers
    var input_array = init: {
        var init_value: [1024]i32 = undefined;
        for (init_value) |*pt, i| {
            pt.* = @intCast(i32, i);
        }
        break :init init_value;
    };

    var input_buffer = c.clCreateBuffer(ctx, c.CL_MEM_READ_ONLY, input_array.len * @sizeOf(i32), null, null);
    if (input_buffer == null) {
        return CLError.CreateBufferFailed;
    }
    defer _ = c.clReleaseMemObject(input_buffer);

    var output_buffer = c.clCreateBuffer(ctx, c.CL_MEM_WRITE_ONLY, input_array.len * @sizeOf(i32), null, null);
    if (output_buffer == null) {
        return CLError.CreateBufferFailed;
    }
    defer _ = c.clReleaseMemObject(output_buffer);

    // Fill input buffer
    if (c.clEnqueueWriteBuffer(command_queue, input_buffer, c.CL_TRUE, 0, input_array.len * @sizeOf(i32), &input_array, 0, null, null) != c.CL_SUCCESS) {
        return CLError.EnqueueWriteBufferFailed;
    }

    // Execute kernel
    if (c.clSetKernelArg(kernel, 0, @sizeOf(c.cl_mem), &input_buffer) != c.CL_SUCCESS) {
        return CLError.SetKernelArgFailed;
    }
    if (c.clSetKernelArg(kernel, 1, @sizeOf(c.cl_mem), &output_buffer) != c.CL_SUCCESS) {
        return CLError.SetKernelArgFailed;
    }

    var global_item_size: usize = input_array.len;
    var local_item_size: usize = 64;
    if (c.clEnqueueNDRangeKernel(command_queue, kernel, 1, null, &global_item_size, &local_item_size, 0, null, null) != c.CL_SUCCESS) {
        return CLError.EnqueueNDRangeKernel;
    }

    var output_array: [1024]i32 = undefined;
    if (c.clEnqueueReadBuffer(command_queue, output_buffer, c.CL_TRUE, 0, output_array.len * @sizeOf(i32), &output_array, 0, null, null) != c.CL_SUCCESS) {
        return CLError.EnqueueReadBufferFailed;
    }

    warn("** done **\n");

    warn("** results **\n");

    for (output_array) |val, i| {
        warn("{} ^ 2 = {}\n", i, val);
    }

    warn("** done, exiting **\n");
}

pub fn main() anyerror!void {
    var device = try get_cl_device();
    try run_test(device);
}
