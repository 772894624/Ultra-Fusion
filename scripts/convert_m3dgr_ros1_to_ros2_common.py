#!/usr/bin/env python3
"""Convert M3DGR ROS1 bags to ROS2 bags with standard common topics.

The M3DGR bags used here contain Livox CustomMsg lidar packets.  This converter
writes those packets as sensor_msgs/msg/PointCloud2 so ROS2 playback does not
need livox_ros_driver or livox_ros_driver2 message packages.
"""

from __future__ import annotations

import argparse
import shutil
import struct
from pathlib import Path

import numpy as np
from rosbags.highlevel import AnyReader
from rosbags.rosbag2 import Writer
from rosbags.typesys import Stores, get_typestore


DEFAULT_COPY_TOPICS = {
    "/livox/mid360/imu",
    "/camera/imu",
    "/odom",
    "/camera/color/image_raw/compressed",
    "/cv_camera/image_raw/compressed",
}

DEFAULT_REMAP_TOPICS = {
    "/camera/aligned_depth_to_color/image_raw/compressedDepth":
        "/camera/aligned_depth_to_color/image_raw",
}


def stamp_to_ns(stamp: object) -> int:
    return int(stamp.sec) * 1_000_000_000 + int(stamp.nanosec)


def make_pointcloud2(custom_msg: object, store: object) -> object:
    time_cls = store.types["builtin_interfaces/msg/Time"]
    header_cls = store.types["std_msgs/msg/Header"]
    field_cls = store.types["sensor_msgs/msg/PointField"]
    cloud_cls = store.types["sensor_msgs/msg/PointCloud2"]

    fields = [
        field_cls("x", 0, field_cls.FLOAT32, 1),
        field_cls("y", 4, field_cls.FLOAT32, 1),
        field_cls("z", 8, field_cls.FLOAT32, 1),
        field_cls("intensity", 12, field_cls.FLOAT32, 1),
        # Ultra-Fusion's Livox PointCloud2 path expects nanoseconds here and
        # converts with * 1e-9 before computing relative scan time.
        field_cls("timestamp", 16, field_cls.FLOAT64, 1),
        field_cls("tag", 24, field_cls.UINT8, 1),
        field_cls("line", 25, field_cls.UINT8, 1),
    ]
    point_step = 26
    points = custom_msg.points
    data = bytearray(point_step * len(points))
    for index, point in enumerate(points):
        struct.pack_into(
            "<ffffdBB",
            data,
            index * point_step,
            float(point.x),
            float(point.y),
            float(point.z),
            float(point.reflectivity),
            float(point.offset_time),
            int(point.tag) & 0xFF,
            int(point.line) & 0xFF,
        )

    src_stamp = custom_msg.header.stamp
    header = header_cls(
        time_cls(int(src_stamp.sec), int(src_stamp.nanosec)),
        str(custom_msg.header.frame_id or "livox_frame"),
    )
    return cloud_cls(
        header,
        1,
        len(points),
        fields,
        False,
        point_step,
        point_step * len(points),
        np.frombuffer(bytes(data), dtype=np.uint8),
        False,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True, type=Path)
    parser.add_argument("--dst", required=True, type=Path)
    parser.add_argument(
        "--lidar-topic",
        default="/livox/mid360/lidar",
        help="Livox CustomMsg source topic; written as PointCloud2 on same topic.",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=0.0,
        help="Optional seconds from bag start to convert. 0 converts full bag.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Remove destination directory if it already exists.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.dst.exists():
        if not args.overwrite:
            raise SystemExit(f"Destination already exists: {args.dst}")
        shutil.rmtree(args.dst)

    store = get_typestore(Stores.ROS2_HUMBLE)
    copy_topics = set(DEFAULT_COPY_TOPICS) | set(DEFAULT_REMAP_TOPICS)
    wanted_topics = copy_topics | {args.lidar_topic}
    written_counts: dict[str, int] = {}

    with AnyReader([args.src]) as reader, Writer(args.dst, version=8) as writer:
        source_connections = [
            conn for conn in reader.connections if conn.topic in wanted_topics
        ]
        if not source_connections:
            raise SystemExit("No requested M3DGR common topics were found")

        end_time = None
        if args.duration > 0.0:
            end_time = reader.start_time + int(args.duration * 1_000_000_000)

        output_connections = {}
        for conn in source_connections:
            if conn.topic == args.lidar_topic:
                output_connections[conn.id] = writer.add_connection(
                    args.lidar_topic,
                    "sensor_msgs/msg/PointCloud2",
                    typestore=store,
                )
                continue

            dst_topic = DEFAULT_REMAP_TOPICS.get(conn.topic, conn.topic)
            output_connections[conn.id] = writer.add_connection(
                dst_topic,
                conn.msgtype,
                typestore=store,
            )

        for conn, timestamp, rawdata in reader.messages(
            connections=source_connections
        ):
            if end_time is not None and timestamp > end_time:
                break

            out_conn = output_connections[conn.id]
            if conn.topic == args.lidar_topic:
                custom_msg = reader.deserialize(rawdata, conn.msgtype)
                cloud_msg = make_pointcloud2(custom_msg, store)
                serialized = store.serialize_cdr(
                    cloud_msg, "sensor_msgs/msg/PointCloud2"
                )
                write_time = stamp_to_ns(custom_msg.header.stamp)
                writer.write(out_conn, write_time, serialized)
            else:
                msg = reader.deserialize(rawdata, conn.msgtype)
                serialized = store.serialize_cdr(msg, conn.msgtype)
                writer.write(out_conn, timestamp, serialized)

            written_counts[out_conn.topic] = written_counts.get(out_conn.topic, 0) + 1

    for topic, count in sorted(written_counts.items()):
        print(f"{topic}: {count}")
    print(f"wrote {args.dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
