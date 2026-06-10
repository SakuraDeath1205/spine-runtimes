/******************************************************************************
 * Spine Runtimes License Agreement
 * Last updated April 5, 2025. Replaces all prior versions.
 *
 * Copyright (c) 2013-2025, Esoteric Software LLC
 *
 * Integration of the Spine Runtimes into software or otherwise creating
 * derivative works of the Spine Runtimes is permitted under the terms and
 * conditions of Section 2 of the Spine Editor License Agreement:
 * http://esotericsoftware.com/spine-editor-license
 *
 * Otherwise, it is permitted to integrate the Spine Runtimes into software
 * or otherwise create derivative works of the Spine Runtimes (collectively,
 * "Products"), provided that each user of the Products must obtain their own
 * Spine Editor license and redistribution of the Products in any form must
 * include this license and copyright notice.
 *
 * THE SPINE RUNTIMES ARE PROVIDED BY ESOTERIC SOFTWARE LLC "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL ESOTERIC SOFTWARE LLC BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES,
 * BUSINESS INTERRUPTION, OR LOSS OF USE, DATA, OR PROFITS) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THE SPINE RUNTIMES, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *****************************************************************************/

import Foundation
import SpineC

/// Convenient drawable that combines skeleton, animation state, and rendering
public class SkeletonDrawable {
    private let _drawable: UnsafeMutablePointer<spine_skeleton_drawable_wrapper>

    public let skeleton: Skeleton
    public let animationState: AnimationState
    public let animationStateData: AnimationStateData

    public init(skeletonData: SkeletonData) {
        guard let drawable = spine_skeleton_drawable_create(skeletonData._ptr.assumingMemoryBound(to: spine_skeleton_data_wrapper.self)) else {
            fatalError("Failed to create skeleton drawable")
        }
        self._drawable = drawable

        // Get references to the skeleton and animation state
        guard let skeletonPtr = spine_skeleton_drawable_get_skeleton(drawable) else {
            spine_skeleton_drawable_dispose(drawable)
            fatalError("Failed to get skeleton from drawable")
        }
        self.skeleton = Skeleton(fromPointer: skeletonPtr)

        guard let animationStatePtr = spine_skeleton_drawable_get_animation_state(drawable) else {
            spine_skeleton_drawable_dispose(drawable)
            fatalError("Failed to get animation state from drawable")
        }
        self.animationState = AnimationState(fromPointer: animationStatePtr)

        guard let animationStateDataPtr = spine_skeleton_drawable_get_animation_state_data(drawable) else {
            spine_skeleton_drawable_dispose(drawable)
            fatalError("Failed to get animation state data from drawable")
        }
        self.animationStateData = AnimationStateData(fromPointer: animationStateDataPtr)
    }

    /// Update the animation state and process events
    public func update(_ delta: Float) {
        // Update animation state
        animationState.update(delta)

        // Process events
        if let eventsPtr = spine_skeleton_drawable_get_animation_state_events(_drawable) {
            let numEvents = Int(spine_animation_state_events_get_num_events(eventsPtr))

            for i in 0..<numEvents {
                // Get event type
                let eventTypeValue = spine_animation_state_events_get_event_type(eventsPtr, Int32(i))
                guard let type = EventType.fromValue(Int32(eventTypeValue)) else {
                    continue
                }

                // Get track entry
                if let trackEntryPtr = spine_animation_state_events_get_track_entry(eventsPtr, Int32(i)) {
                    let trackEntry = TrackEntry(fromPointer: trackEntryPtr)

                    // Get event (may be null)
                    let eventPtr = spine_animation_state_events_get_event(eventsPtr, Int32(i))
                    let event = eventPtr != nil ? Event(fromPointer: eventPtr!) : nil

                    // Call track entry listener if registered
                    if let trackListener = AnimationStateEventManager.instance.getTrackEntryListener(animationState, trackEntry) {
                        trackListener(type, trackEntry, event)
                    }

                    // Call global state listener
                    animationState.listener?(type, trackEntry, event)

                    // Remove listener if track entry is being disposed
                    if type == .dispose {
                        AnimationStateEventManager.instance.removeTrackEntry(animationState, trackEntry)
                    }
                }
            }

            // Reset events for next frame
            spine_animation_state_events_reset(eventsPtr)
        }

        // Apply animation state to skeleton
        _ = animationState.apply(skeleton)

        // Update skeleton physics and world transforms
        skeleton.update(delta)
        skeleton.updateWorldTransform(Physics.update)
    }

    /// Render the skeleton and get render commands
    public func render() -> RenderCommand? {
        guard let renderCommand = spine_skeleton_drawable_render(_drawable) else {
            return nil
        }
        return RenderCommand(fromPointer: renderCommand)
    }

    public func renderUnbatched() -> RenderCommand? {
        guard let renderCommand = spine_skeleton_drawable_render_unbatched(_drawable) else {
            return nil
        }

        return RenderCommand(fromPointer: renderCommand)
    }

    deinit {
        AnimationStateEventManager.instance.clearState(animationState)
        spine_skeleton_drawable_dispose(_drawable)
    }
}
