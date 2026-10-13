#!/usr/bin/env ruby
#
# 에디터(IntelliJ) 미리보기용 상대경로 `](../../assets/...)` 를
# 배포용 루트 절대경로 `](/assets/...)` 로 바꾼다

Jekyll::Hooks.register [:posts, :pages], :pre_render do |doc|
  doc.content = doc.content.gsub(%r{\]\((?:\.\./)+assets/}, '](/assets/')
end
