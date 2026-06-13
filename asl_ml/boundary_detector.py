import numpy as np
from collections import deque


class BoundaryDetector:
    """
    Monitors hand movement velocity to detect sign boundaries.
    
    Strategy:
    - High velocity = active signing (hands moving)
    - Low velocity sustained = sign completed (return to rest position)
    """

    def __init__(
        self,
        window_size=30,             # Frames to buffer for classifier
        velocity_threshold=0.02,    # Below this = "resting"
        rest_frames_needed=5,       # Consecutive low-velocity frames = boundary
        min_signing_frames=10,      # Min frames before accepting a sign
    ):
        self.window_size = window_size
        self.velocity_threshold = velocity_threshold
        self.rest_frames_needed = rest_frames_needed
        self.min_signing_frames = min_signing_frames

        self.frame_buffer = deque(maxlen=window_size)  # Keypoints buffer
        self.velocity_buffer = deque(maxlen=20)        # Recent velocities
        self.rest_frame_count = 0
        self.active_signing_frames = 0
        self.prev_keypoints = None
        self.state = "idle"  # idle | signing | boundary

    def update(self, keypoints):
        """
        Process a new keypoint frame.
        
        Args:
            keypoints: np.array(126,) or None
            
        Returns:
            dict with:
                state: 'idle' | 'signing' | 'boundary'
                buffer: list of frames (if boundary detected)
                should_classify: bool
        """
        result = {
            "state": "idle",
            "buffer": None,
            "should_classify": False,
            "velocity": 0.0
        }

        # No hands detected
        if keypoints is None:
            velocity = 0.0
            self.velocity_buffer.append(0.0)
            
            if self.state == "signing":
                self.rest_frame_count += 1
                if self.rest_frame_count >= self.rest_frames_needed:
                    # Sign ended
                    if self.active_signing_frames >= self.min_signing_frames:
                        result["state"] = "boundary"
                        result["buffer"] = list(self.frame_buffer)
                        result["should_classify"] = True
                        self._reset()
                        return result
                    else:
                        # Too short — false positive
                        self._reset()
            
            result["state"] = "idle"
            result["velocity"] = 0.0
            return result

        # Calculate velocity
        velocity = self._calc_velocity(keypoints)
        self.velocity_buffer.append(velocity)
        result["velocity"] = velocity

        # Buffer the frame
        self.frame_buffer.append(keypoints.copy())

        # State machine
        if velocity > self.velocity_threshold:
            # Active movement detected
            self.state = "signing"
            self.rest_frame_count = 0
            self.active_signing_frames += 1
            result["state"] = "signing"

        elif self.state == "signing":
            # Movement stopped
            self.rest_frame_count += 1
            result["state"] = "signing"  # Still in sign until boundary confirmed

            if self.rest_frame_count >= self.rest_frames_needed:
                if self.active_signing_frames >= self.min_signing_frames:
                    # Valid sign completed
                    result["state"] = "boundary"
                    result["buffer"] = list(self.frame_buffer)
                    result["should_classify"] = True
                    self._reset()
                    return result
                else:
                    self._reset()
        else:
            result["state"] = "idle"

        self.prev_keypoints = keypoints.copy()
        return result

    def _calc_velocity(self, keypoints):
        """Calculate movement velocity from wrist landmark."""
        if self.prev_keypoints is None:
            self.prev_keypoints = keypoints.copy()
            return 0.0

        # Use first hand wrist (indices 0-2)
        prev_wrist = self.prev_keypoints[:3]
        curr_wrist = keypoints[:3]
        
        # Also check second hand wrist (indices 63-65)
        prev_wrist2 = self.prev_keypoints[63:66]
        curr_wrist2 = keypoints[63:66]
        
        vel1 = float(np.linalg.norm(curr_wrist - prev_wrist))
        vel2 = float(np.linalg.norm(curr_wrist2 - prev_wrist2))
        
        return max(vel1, vel2)  # Use the more active hand

    def get_padded_buffer(self):
        """
        Return buffer padded/trimmed to exactly window_size frames.
        Needed for model input consistency.
        """
        buf = list(self.frame_buffer)
        
        if len(buf) == 0:
            return np.zeros((self.window_size, 126), dtype=np.float32)
        
        if len(buf) < self.window_size:
            # Pad with first frame (repeat start)
            pad = [buf[0]] * (self.window_size - len(buf))
            buf = pad + buf
        elif len(buf) > self.window_size:
            # Sample evenly
            indices = np.linspace(0, len(buf)-1, self.window_size, dtype=int)
            buf = [buf[i] for i in indices]
        
        return np.array(buf, dtype=np.float32)

    def _reset(self):
        self.state = "idle"
        self.rest_frame_count = 0
        self.active_signing_frames = 0
        self.frame_buffer.clear()
        self.prev_keypoints = None

    def get_avg_velocity(self):
        """Get average velocity of recent frames."""
        if not self.velocity_buffer:
            return 0.0
        return float(np.mean(list(self.velocity_buffer)))

    def force_classify(self):
        """
        Force classification of current buffer.
        Use when user presses a 'done signing' button.
        """
        if len(self.frame_buffer) >= self.min_signing_frames:
            buf = self.get_padded_buffer()
            self._reset()
            return buf
        return None
