import re
import requests
import streamlit as st

# Same Supabase Edge Function already used by the Flutter app.
EXTRACTOR_URL = "https://emkehfwntauhgmdsrcmw.supabase.co/functions/v1/extract"
SUPABASE_ANON_KEY = "sb_publishable_hrN7MEBF52uf5-nJ6OKDnw_tpclR6Om"

st.set_page_config(page_title="Pak Downloader", page_icon="⬇️", layout="centered")

PLATFORM_PATTERNS = {
    "TikTok": re.compile(r"tiktok\.com", re.I),
    "Instagram": re.compile(r"instagram\.com", re.I),
    "Facebook": re.compile(r"facebook\.com|fb\.watch", re.I),
    "YouTube": re.compile(r"youtube\.com|youtu\.be", re.I),
}


def detect_platform(url: str) -> str:
    for name, pattern in PLATFORM_PATTERNS.items():
        if pattern.search(url):
            return name
    return "Unknown"


def looks_like_video_link(url: str) -> bool:
    if not url.startswith(("http://", "https://")):
        return False
    return any(p.search(url) for p in PLATFORM_PATTERNS.values())


st.markdown(
    """
    <style>
    .stApp { background-color: #0B1210; }
    .main-title {
        font-size: 2rem; font-weight: 800; color: white;
        text-align: center; margin-bottom: 0.2rem;
    }
    .sub-title {
        text-align: center; color: #9CA3AF; margin-bottom: 2rem;
    }
    </style>
    """,
    unsafe_allow_html=True,
)

st.markdown('<div class="main-title">📥 Pak Downloader</div>', unsafe_allow_html=True)
st.markdown(
    '<div class="sub-title">TikTok · Instagram · Facebook · YouTube</div>',
    unsafe_allow_html=True,
)

url = st.text_input("Paste video link here", placeholder="https://...")

if url:
    if not looks_like_video_link(url):
        st.error("That doesn't look like a supported video link.")
    else:
        platform = detect_platform(url)
        st.info(f"Detected: **{platform}** video")

        if st.button("⬇️ Resolve & Download", use_container_width=True):
            with st.spinner("Resolving video..."):
                try:
                    resp = requests.get(
                        EXTRACTOR_URL,
                        params={"url": url},
                        headers={
                            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                            "apikey": SUPABASE_ANON_KEY,
                        },
                        timeout=30,
                    )
                    data = resp.json()
                except Exception as e:
                    st.error(f"Request failed: {e}")
                    st.stop()

                if resp.status_code != 200 or not data.get("video_url"):
                    st.error(data.get("error", "Could not resolve a video from this link."))
                    st.stop()

                video_url = data["video_url"]
                title = data.get("title") or "video"

            with st.spinner("Downloading video..."):
                try:
                    video_resp = requests.get(video_url, timeout=60)
                    video_resp.raise_for_status()
                except Exception as e:
                    st.error(f"Download failed: {e}")
                    st.stop()

            st.success("Video ready!")
            st.video(video_resp.content)
            st.download_button(
                label="Save video to device",
                data=video_resp.content,
                file_name=f"{title[:40] or 'pak_video'}.mp4",
                mime="video/mp4",
                use_container_width=True,
            )

st.caption("For personal use. Please respect content creators' rights.")
  
