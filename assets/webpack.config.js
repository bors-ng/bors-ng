const path = require('path');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const TerserPlugin = require('terser-webpack-plugin');
const OptimizeCSSAssetsPlugin = require('optimize-css-assets-webpack-plugin');
const CopyWebpackPlugin = require('copy-webpack-plugin');

module.exports = (env, options) => ({
  devtool: "source-map",
  optimization: {
    minimize: true,
    minimizer: [
      new TerserPlugin({}),
      new OptimizeCSSAssetsPlugin({})
    ]
  },
  entry: {
    './js/app.js': ['./js/app.js']
  },
  output: {
    filename: 'app.js',
    path: path.resolve(__dirname, '../priv/static/js')
  },
  stats: {
    colors: !/^win/i.test(process.platform)
  },
  module: {
    rules: [
      {
        test: /\.js$/,
        exclude: /node_modules/
      },
      {
        test: /\.css$/,
        use: [MiniCssExtractPlugin.loader, 'css-loader']
      }
    ]
  },
  plugins: [
    new MiniCssExtractPlugin({ filename: '../css/app.css' }),
    new CopyWebpackPlugin({ patterns: [ { from: 'static/', to: '../' } ] })
  ]
});
