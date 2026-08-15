# 강서중 과학수업 블로그

설치할 프로그램 없이 동작하는 정적 블로그입니다. 글은 마크다운 파일로 쓰고, 폴더를 그대로 웹 호스팅에 올리면 됩니다.

## 미리보기

PowerShell에서 블로그 폴더를 연 뒤 실행합니다.

```bash
powershell -ExecutionPolicy Bypass -File serve.ps1
```

브라우저에서 http://localhost:8080 으로 접속합니다. 종료는 Ctrl+C.

> `index.html`을 더블클릭해서 여는 방식은 동작하지 않습니다. 브라우저가 보안상 로컬 파일 읽기를 막기 때문에, 위 서버로 열어야 합니다.

## 글 쓰는 법

1. `posts` 폴더에 `2026-08-20-제목.md` 형식으로 파일을 만듭니다.
2. 파일 맨 위에 아래 정보를 적습니다.

   ```
   ---
   title: 글 제목
   date: 2026-08-20
   category: 수업자료
   tags: 과학, 실험
   summary: 목록에 보일 한 줄 요약
   ---
   ```

   `summary`를 비워 두면 첫 문단이 자동으로 쓰입니다.
3. 그 아래에 본문을 마크다운으로 씁니다.
4. `posts/index.json` 목록에 파일 이름을 추가합니다.

`category`는 목록 상단의 분류 버튼으로 자동으로 만들어집니다.

## 사진 넣기

`assets` 폴더에 이미지를 넣고 본문에서 이렇게 씁니다.

```
![실험 장면](assets/experiment.jpg)
```

## 인터넷에 올리기

폴더 전체를 그대로 올리면 되는 무료 호스팅을 쓰면 됩니다.

- **GitHub Pages** — GitHub에 저장소를 만들고 파일을 올린 뒤, Settings → Pages에서 브랜치를 지정합니다.
- **Netlify / Vercel** — 폴더를 끌어다 놓으면 바로 주소가 생깁니다.

빌드 설정은 필요 없습니다. 정적 파일만으로 동작합니다.

## 폴더 구성

```
index.html             글 목록
post.html              글 본문
assets/style.css       디자인
assets/app.js          마크다운 변환, 목록·본문 렌더링
assets/school-mark.png 학교 교표 (헤더 마크 · 파비콘)
assets/school-logo.png 학교 가로형 로고 (원본, 현재 미사용)
posts/index.json       글 목록 (파일 이름)
posts/*.md             글 원본
serve.ps1              로컬 미리보기 서버
```

## 학교 마크

헤더 마크와 파비콘은 [강서중학교 홈페이지](https://gangseo.gwe.ms.kr/)의 교표를 내려받아 정사각형으로 잘라 쓰고 있습니다. 바꾸려면 `assets/school-mark.png`를 같은 이름의 다른 이미지로 교체하면 됩니다.

## 블로그 이름 바꾸기

`index.html`, `post.html`, `assets/app.js`의 `강서중 과학수업` 부분을 원하는 이름으로 바꾸면 됩니다.

## 색상 바꾸기

`assets/style.css` 맨 위에 추천 색상 조합이 주석으로 정리되어 있습니다. `--accent`(강조색)와 `--accent-soft`(연한 배경) 값을 바꾸면 전체 색이 함께 바뀝니다. 밝은 모드용 한 곳, 어두운 모드용 두 곳에 같은 이름이 있으니 세 곳 모두 바꿔야 합니다.
